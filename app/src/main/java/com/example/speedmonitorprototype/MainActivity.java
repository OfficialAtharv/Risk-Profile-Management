package com.example.speedmonitorprototype;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.pm.PackageManager;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import com.github.anastr.speedviewlib.SpeedView;

import java.io.IOException;

import okhttp3.OkHttpClient;
import okhttp3.logging.HttpLoggingInterceptor;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;
import retrofit2.Retrofit;
import retrofit2.converter.gson.GsonConverterFactory;
import retrofit2.http.Body;
import retrofit2.http.POST;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;
import android.location.Location;


public class MainActivity extends AppCompatActivity {

    TextView txtSpeed, txtStatus;
    Button btnTrip, btnIncrease, btnDecrease;
    SpeedView speedView;

    boolean tripStarted = false;
    boolean emailSent = false;

    int currentSpeed = 0;
    final int SPEED_LIMIT = 60;

    long lastNotificationTime = 0;
    final long NOTIFICATION_COOLDOWN = 30_000;

    // 🔥 CHANGE THIS TO YOUR N8N DOMAIN
    private static final String BASE_URL = "https://atharvnova.app.n8n.cloud/";
    private FusedLocationProviderClient fusedLocationClient;
    private LocationCallback locationCallback;
    private LocationRequest locationRequest;
    private static final int LOCATION_PERMISSION_REQUEST_CODE = 200;



    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        createNotificationChannel();
        requestNotificationPermission();
        requestLocationPermission();
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this);



        txtSpeed = findViewById(R.id.txtSpeed);
        txtStatus = findViewById(R.id.txtStatus);
        btnTrip = findViewById(R.id.btnTrip);
        btnIncrease = findViewById(R.id.btnIncrease);
        btnDecrease = findViewById(R.id.btnDecrease);
        speedView = findViewById(R.id.speedView);

        speedView.setMaxSpeed(120);
        speedView.setUnit("km/h");
        speedView.speedTo(0);

        btnTrip.setOnClickListener(v -> {
            tripStarted = !tripStarted;
            emailSent = false;
            lastNotificationTime = 0;

            if (tripStarted) {
                txtStatus.setText("Status: Trip Started");
                btnTrip.setText("End Trip");
                startLocationUpdates();
            } else {
                txtStatus.setText("Status: Trip Ended");
                btnTrip.setText("Start Trip");
            }
        });

        btnIncrease.setOnClickListener(v -> updateSpeed(currentSpeed + 5));
        btnDecrease.setOnClickListener(v -> updateSpeed(Math.max(0, currentSpeed - 5)));
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this);

        locationRequest = new LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY,
                2000 // 2 seconds interval
        ).build();

        locationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(LocationResult locationResult) {
                if (locationResult == null) return;

                for (Location location : locationResult.getLocations()) {

                    float speedKmh = location.getSpeed() * 3.6f;

                    currentSpeed = (int) speedKmh;

                    speedView.speedTo(currentSpeed);
                    txtSpeed.setText("Speed: " + currentSpeed + " km/h");
                }
            }
        };
        locationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(LocationResult locationResult) {
                if (locationResult == null) return;

                for (Location location : locationResult.getLocations()) {

                    double latitude = location.getLatitude();
                    double longitude = location.getLongitude();

                    float speedInMetersPerSecond = location.getSpeed();
                    float speedInKmH = speedInMetersPerSecond * 3.6f;

                    currentSpeed = (int) speedInKmH;

                    speedView.speedTo(currentSpeed);
                    txtSpeed.setText("Speed: " + currentSpeed + " km/h");

                    Log.d("GPS", "Lat: " + latitude +
                            " Lon: " + longitude +
                            " Speed: " + currentSpeed);
                }
            }
        };


    }

    private void updateSpeed(int newSpeed) {
        currentSpeed = newSpeed;

        speedView.speedTo(currentSpeed);
        txtSpeed.setText("Speed: " + currentSpeed + " km/h");

        if (!tripStarted) return;

        if (currentSpeed > SPEED_LIMIT) {

            txtStatus.setText("Status: OVERSPEED");

            long now = System.currentTimeMillis();
            if (now - lastNotificationTime > NOTIFICATION_COOLDOWN) {
                showSpeedAlertNotification(currentSpeed);
                lastNotificationTime = now;
            }

            if (!emailSent) {
                emailSent = true;
                sendSpeedToN8n(currentSpeed);

                Toast.makeText(
                        this,
                        "Overspeed detected. Automation triggered!",
                        Toast.LENGTH_SHORT
                ).show();
            }

        } else {
            txtStatus.setText("Status: Within limit");
        }
    }

    // 🚀 SEND DATA TO N8N WEBHOOK
    private void sendSpeedToN8n(int speed) {

        HttpLoggingInterceptor interceptor = new HttpLoggingInterceptor();
        interceptor.setLevel(HttpLoggingInterceptor.Level.BODY);

        OkHttpClient client = new OkHttpClient.Builder()
                .addInterceptor(interceptor)
                .build();

        Retrofit retrofit = new Retrofit.Builder()
                .baseUrl(BASE_URL)
                .client(client)
                .addConverterFactory(GsonConverterFactory.create())
                .build();

        ApiService apiService = retrofit.create(ApiService.class);

        SpeedRequest request = new SpeedRequest(
                "28.atharvkulkarni@gmail.com",
                speed,
                System.currentTimeMillis()
        );

        apiService.sendSpeed(request).enqueue(new Callback<Void>() {
            @Override
            public void onResponse(Call<Void> call, Response<Void> response) {
                if (response.isSuccessful()) {
                    Log.d("N8N", "Webhook triggered successfully");
                } else {
                    Log.e("N8N", "Error: " + response.code());
                }
            }

            @Override
            public void onFailure(Call<Void> call, Throwable t) {
                Log.e("N8N", "Network error", t);
            }
        });
    }

    // 🔔 Notification Channel
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            NotificationChannel channel = new NotificationChannel(
                    "speed_alert_channel",
                    "Speed Alert Notifications",
                    NotificationManager.IMPORTANCE_HIGH
            );

            channel.setDescription("Alerts when vehicle speed exceeds limit");
            channel.enableVibration(true);

            NotificationManager manager =
                    getSystemService(NotificationManager.class);

            manager.createNotificationChannel(channel);
        }
    }

    private void showSpeedAlertNotification(int speed) {

        Notification notification =
                new NotificationCompat.Builder(this, "speed_alert_channel")
                        .setSmallIcon(R.drawable.ic_launcher_foreground)
                        .setContentTitle("Overspeed Alert")
                        .setContentText(
                                "Speed exceeded! Current speed: " + speed + " km/h"
                        )
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setAutoCancel(true)
                        .build();

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            return;
        }

        NotificationManagerCompat.from(this)
                .notify(101, notification);
    }

    private void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED) {

                ActivityCompat.requestPermissions(
                        this,
                        new String[]{Manifest.permission.POST_NOTIFICATIONS},
                        100
                );
            }
        }
    }
    private void requestLocationPermission() {

        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
        ) != PackageManager.PERMISSION_GRANTED) {

            ActivityCompat.requestPermissions(
                    this,
                    new String[]{
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION
                    },
                    LOCATION_PERMISSION_REQUEST_CODE
            );
        }
    }
    private void startLocationUpdates() {

        LocationRequest locationRequest = LocationRequest.create();
        locationRequest.setInterval(3000); // every 3 seconds
        locationRequest.setFastestInterval(2000);
        locationRequest.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY);

        if (ActivityCompat.checkSelfPermission(this,
                Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            return;
        }

        fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                null
        );
    }


    // 🔌 Retrofit API Interface
    public interface ApiService {
        @POST("webhook/overspeed")
        Call<Void> sendSpeed(@Body SpeedRequest request);
    }
    @Override
    public void onRequestPermissionsResult(int requestCode,
                                           String[] permissions,
                                           int[] grantResults) {

        super.onRequestPermissionsResult(requestCode, permissions, grantResults);

        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {

            if (grantResults.length > 0
                    && grantResults[0] == PackageManager.PERMISSION_GRANTED) {

                Toast.makeText(this,
                        "Location Permission Granted",
                        Toast.LENGTH_SHORT).show();

            } else {

                Toast.makeText(this,
                        "Location Permission Denied",
                        Toast.LENGTH_SHORT).show();
            }
        }
    }


    // 📦 Data Model
    public static class SpeedRequest {
        String email;
        int speed;
        long timestamp;

        public SpeedRequest(String email, int speed, long timestamp) {
            this.email = email;
            this.speed = speed;
            this.timestamp = timestamp;
        }
    }
}
