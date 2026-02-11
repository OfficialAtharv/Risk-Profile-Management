package com.riskprofile.riskbackend.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Min;

public class SpeedRequest {

    @Email
    private String userEmail;

    @Min(0)
    private int speed;

    public String getUserEmail() {
        return userEmail;
    }

    public void setUserEmail(String userEmail) {
        this.userEmail = userEmail;
    }

    public int getSpeed() {
        return speed;
    }

    public void setSpeed(int speed) {
        this.speed = speed;
    }
}
