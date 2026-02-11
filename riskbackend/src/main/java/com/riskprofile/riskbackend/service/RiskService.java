package com.riskprofile.riskbackend.service;

import com.riskprofile.riskbackend.client.EmailClient;
import com.riskprofile.riskbackend.dto.SpeedRequest;
import org.springframework.stereotype.Service;

@Service
public class RiskService {

    private static final int SPEED_LIMIT = 80;
    private final EmailClient emailClient;

    public RiskService(EmailClient emailClient) {
        this.emailClient = emailClient;
    }

    public void processSpeed(SpeedRequest request) {
        if (request.getSpeed() > SPEED_LIMIT) {
            emailClient.sendAlert(
                request.getUserEmail(),
                request.getSpeed()
            );
        }
    }
}
