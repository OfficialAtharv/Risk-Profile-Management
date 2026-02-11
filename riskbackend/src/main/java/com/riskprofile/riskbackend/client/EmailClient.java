package com.riskprofile.riskbackend.client;

import java.util.Map;

import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

@Component
public class EmailClient {

    private final RestTemplate restTemplate;

    public EmailClient(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    public void sendAlert(String email, int speed) {

        restTemplate.postForObject(
            "http://localhost:8080/email/send",
            Map.of(
                "to", email,
                "subject", "Overspeed Alert",
                "body", "Your speed reached " + speed + " km/h"
            ),
            String.class
        );
    }
}
