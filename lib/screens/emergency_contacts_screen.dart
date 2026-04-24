import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;

  CollectionReference<Map<String, dynamic>> get _contactsRef {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .collection('emergency_contacts');
  }

  Future<void> _showContactDialog({
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController =
    TextEditingController(text: existing?['name']?.toString() ?? '');
    final phoneController =
    TextEditingController(text: existing?['phone']?.toString() ?? '');
    final emailController =
    TextEditingController(text: existing?['email']?.toString() ?? '');

    final bool isEdit = docId != null;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            isEdit ? 'Edit Emergency Contact' : 'Add Emergency Contact',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(
                    controller: nameController,
                    label: 'Name',
                    hint: 'Enter contact name',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    controller: phoneController,
                    label: 'Phone',
                    hint: 'Enter phone number',
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Phone number is required';
                      }
                      if (value.trim().length < 8) {
                        return 'Enter a valid phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    controller: emailController,
                    label: 'Email',
                    hint: 'Enter email address',
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                      if (!regex.hasMatch(value.trim())) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF8B95A7)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final now = FieldValue.serverTimestamp();

                try {
                  if (isEdit) {
                    await _contactsRef.doc(docId).update({
                      'name': nameController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'email': emailController.text.trim(),
                      'updatedAt': now,
                    });
                  } else {
                    final existingPrimary = await _contactsRef
                        .where('isPrimary', isEqualTo: true)
                        .limit(1)
                        .get();

                    final isFirstPrimary = existingPrimary.docs.isEmpty;

                    await _contactsRef.add({
                      'name': nameController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'email': emailController.text.trim(),
                      'isPrimary': isFirstPrimary,
                      'createdAt': now,
                      'updatedAt': now,
                    });
                  }

                  if (mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save contact: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
              child: Text(isEdit ? 'Update' : 'Add'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
  }

  Future<void> _setPrimaryContact(String selectedDocId) async {
    try {
      final snapshot = await _contactsRef.get();
      final batch = FirebaseFirestore.instance.batch();

      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isPrimary': doc.id == selectedDocId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primary contact updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update primary contact: $e')),
      );
    }
  }

  Future<void> _deleteContact(String docId, bool wasPrimary) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Contact'),
        content: const Text('Are you sure you want to delete this contact?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _contactsRef.doc(docId).delete();

      if (wasPrimary) {
        final remaining = await _contactsRef.get();

        if (remaining.docs.isNotEmpty) {
          final alreadyPrimary = remaining.docs.any(
                (doc) => doc.data()['isPrimary'] == true,
          );

          if (!alreadyPrimary) {
            await remaining.docs.first.reference.update({
              'isPrimary': true,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete contact: $e')),
      );
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFFB2BDD0)),
        hintStyle: const TextStyle(color: Color(0xFF6B7280)),
        filled: true,
        fillColor: const Color(0xFF111C35),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF22304D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF3B82F6)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(
        body: Center(
          child: Text('User not logged in'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050816),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Emergency Contacts',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showContactDialog(),
        backgroundColor: const Color(0xFF3B82F6),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _contactsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Error loading contacts: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = [...(snapshot.data?.docs ?? [])];

          docs.sort((a, b) {
            final aCreated = a.data()['createdAt'] as Timestamp?;
            final bCreated = b.data()['createdAt'] as Timestamp?;

            if (aCreated == null && bCreated == null) return 0;
            if (aCreated == null) return 1;
            if (bCreated == null) return -1;

            return aCreated.compareTo(bCreated);
          });

          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No emergency contacts added yet.\nTap + to add one.',
                  style: TextStyle(
                    color: Color(0xFF8B95A7),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final name = data['name']?.toString() ?? '';
              final phone = data['phone']?.toString() ?? '';
              final email = data['email']?.toString() ?? '';
              final isPrimary = data['isPrimary'] == true;

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1A31),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isPrimary
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF1A2743),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name.isEmpty ? 'Unnamed Contact' : name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isPrimary)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withOpacity(0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Primary',
                                style: TextStyle(
                                  color: Color(0xFF7DB4FF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Phone: ${phone.isEmpty ? "--" : phone}',
                        style: const TextStyle(
                          color: Color(0xFFB2BDD0),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Email: ${email.isEmpty ? "--" : email}',
                        style: const TextStyle(
                          color: Color(0xFFB2BDD0),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _showContactDialog(
                              docId: doc.id,
                              existing: data,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(
                                color: Color(0xFF2A344A),
                              ),
                            ),
                            child: const Text('Edit'),
                          ),
                          OutlinedButton(
                            onPressed: isPrimary
                                ? null
                                : () => _setPrimaryContact(doc.id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF7DB4FF),
                              side: const BorderSide(
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                            child: const Text('Set Primary'),
                          ),
                          OutlinedButton(
                            onPressed: () => _deleteContact(doc.id, isPrimary),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFF7A80),
                              side: const BorderSide(
                                color: Color(0x66FF5C63),
                              ),
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}


