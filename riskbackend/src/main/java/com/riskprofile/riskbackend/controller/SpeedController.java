package com.riskprofile.riskbackend.controller;

import java.util.HashMap;
import java.util.Map;

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

    // Build request body as Map (safe & clean)
    Map<String, Object> payload = new HashMap<>();
    payload.put("to", email);
    payload.put("subject", "🚨 Risk Alert: Overspeed Detected");

    payload.put(
        "body",
        "Dear User,\n\n" +
            "This is an automated alert from the Risk Profile Management System.\n\n" +
            "🚗 Current Speed: " + speed + " km/h\n" +
            "⚠️ Permitted Limit: 60 km/h\n\n" +
            "Driving at high speeds increases the risk of accidents.\n" +
            "Please slow down and drive responsibly.\n\n" +
            "Stay safe,\n" +
            "Risk Profile Management Team");

    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.APPLICATION_JSON);

    HttpEntity<Map<String, Object>> requestEntity = new HttpEntity<>(payload, headers);

    restTemplate.postForEntity(
        emailServiceUrl,
        requestEntity,
        String.class);

    System.out.println("📧 Email request sent successfully");
  }

}
