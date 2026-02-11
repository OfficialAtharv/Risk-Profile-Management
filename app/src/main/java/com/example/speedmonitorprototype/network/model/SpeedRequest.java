package com.example.speedmonitorprototype.network.model;

public class SpeedRequest {

    private String userEmail;
    private int speed;

    public SpeedRequest(String userEmail, int speed) {
        this.userEmail = userEmail;
        this.speed = speed;
    }

    public String getUserEmail() {
        return userEmail;
    }

    public int getSpeed() {
        return speed;
    }
}
