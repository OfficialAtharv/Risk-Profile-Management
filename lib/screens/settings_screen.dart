import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _appNotificationEnabled = true;
  bool _callingAlertEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _appNotificationEnabled = prefs.getBool('appNotification') ?? true;
      _callingAlertEnabled = prefs.getBool('callingAlert') ?? true;
    });
  }

  Future<void> _updateAppNotification(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appNotification', value);

    setState(() {
      _appNotificationEnabled = value;
    });
  }

  Future<void> _updateCallingAlert(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('callingAlert', value);

    setState(() {
      _callingAlertEnabled = value;
    });
  }

  Future<void> _updateDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);

    themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Logout",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentThemeMode, _) {
        final isDarkMode = currentThemeMode == ThemeMode.dark;

        return Scaffold(
          backgroundColor: const Color(0xFF050816),
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Settings",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Manage your preferences",
                    style: TextStyle(
                      color: Color(0xFF8B95A7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 28),

                  _buildSectionTitle(
                    icon: Icons.notifications_none_rounded,
                    title: "Notifications",
                  ),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    children: [
                      _buildToggleRow(
                        title: "App Alerts",
                        subtitle: "Get notified about overspeeding",
                        value: _appNotificationEnabled,
                        onChanged: _updateAppNotification,
                      ),
                      _buildDivider(),
                      _buildToggleRow(
                        title: "Emergency Calling",
                        subtitle: "Auto-call emergency contact",
                        value: _callingAlertEnabled,
                        onChanged: _updateCallingAlert,
                      ),
                      _buildDivider(),
                      _buildInfoRow(
                        icon: Icons.phone_outlined,
                        title: "Emergency Contact",
                        subtitle: "+1 (555) 123-4567",
                        onTap: () {},
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  _buildSectionTitle(
                    icon: Icons.dark_mode_outlined,
                    title: "Appearance",
                  ),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    children: [
                      _buildToggleRow(
                        title: "Dark Mode",
                        subtitle: "Use dark theme",
                        value: isDarkMode,
                        onChanged: _updateDarkMode,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  _buildSectionTitle(
                    icon: Icons.person_outline_rounded,
                    title: "Account",
                  ),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    children: [
                      _buildInfoRow(
                        icon: Icons.mail_outline_rounded,
                        title: "Email",
                        subtitle: user?.email ?? 'No user',
                        onTap: () {},
                      ),
                      _buildDivider(),
                      _buildInfoRow(
                        icon: Icons.person_outline_rounded,
                        title: "Profile",
                        subtitle: "View and edit profile",
                        onTap: () {},
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _handleLogout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF5C63),
                        side: const BorderSide(
                          color: Color(0x66FF5C63),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: const Color(0xFF0B1222),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.logout_rounded, size: 20),
                          SizedBox(width: 10),
                          Text(
                            "Logout",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: const Color(0xFF4DA3FF),
          size: 22,
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C1630),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF1A2743),
          width: 1,
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8B95A7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF3B82F6),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFF2A344A),
            trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFFB2BDD0),
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8B95A7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF7B879C),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFF18233E),
    );
  }
}