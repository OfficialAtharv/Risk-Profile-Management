package com.example.speedmonitorprototype;

import android.os.Bundle;
import android.widget.Button;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

public class MainActivity extends AppCompatActivity {

    TextView txtSpeed, txtStatus;
    SeekBar speedSeekBar;
    Button btnTrip;

    boolean tripStarted = false;
    boolean emailSent = false;

    final int SPEED_LIMIT = 60;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        txtSpeed = findViewById(R.id.txtSpeed);
        txtStatus = findViewById(R.id.txtStatus);
        speedSeekBar = findViewById(R.id.speedSeekBar);
        btnTrip = findViewById(R.id.btnTrip);

        speedSeekBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                txtSpeed.setText("Speed: " + progress + " km/h");

                if (tripStarted) {
                    if (progress > SPEED_LIMIT) {
                        txtStatus.setText("Status: Overspeed Detected");

                        if (!emailSent) {
                            emailSent = true;
                            Toast.makeText(
                                    MainActivity.this,
                                    "Email Triggered (Prototype)",
                                    Toast.LENGTH_SHORT
                            ).show();
                        }

                    } else {
                        txtStatus.setText("Status: Within Speed Limit");
                    }
                }
            }

            @Override
            public void onStartTrackingTouch(SeekBar seekBar) { }

            @Override
            public void onStopTrackingTouch(SeekBar seekBar) { }
        });

        btnTrip.setOnClickListener(v -> {
            tripStarted = !tripStarted;

            if (tripStarted) {
                emailSent = false; // reset for new trip
                btnTrip.setText("End Trip");
                txtStatus.setText("Status: Trip Started");
            } else {
                btnTrip.setText("Start Trip");
                txtStatus.setText("Status: Trip Ended");
            }
        });
    }
}
