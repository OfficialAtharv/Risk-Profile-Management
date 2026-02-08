package com.riskprofile.riskbackend.controller;

import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

import com.riskprofile.riskbackend.dto.SpeedRequest;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/speed")
public class SpeedController {

    private static final int SPEED_LIMIT = 60; // keep same as Android

    @PostMapping("/update")
    public ResponseEntity<String> updateSpeed(@Valid @RequestBody SpeedRequest request) {

        int speed = request.getSpeed();
        String email = request.getUserEmail();

        System.out.println("🔥 SPEED RECEIVED: " + speed);

        if (speed > SPEED_LIMIT) {
            System.out.println("🚨 OVERSPEED DETECTED → Triggering email");
            triggerEmail(email, speed);
        }

        return ResponseEntity.ok("Speed processed");
    }

    private void triggerEmail(String email, int speed) {

        RestTemplate restTemplate = new RestTemplate();

        String emailServiceUrl = "http://localhost:8080/email/send";

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        String payload = """
            {
                "to": "%s",
                "subject": "Risk Alert",
                "body": "This is an automated alert.\n\nOur system detected that your vehicle crossed the permitted speed limit.\n\nRecorded Speed: %d km/h\n\nImmediate corrective action is advised."
            }
            """.formatted(email, speed);

        HttpEntity<String> requestEntity = new HttpEntity<>(payload, headers);

        restTemplate.postForEntity(
                emailServiceUrl,
                requestEntity,
                String.class
        );

        System.out.println("📧 Email request sent to Email Service");
    }
}
