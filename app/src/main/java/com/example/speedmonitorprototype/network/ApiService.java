package com.example.speedmonitorprototype.network;

import com.example.speedmonitorprototype.network.model.SpeedRequest;


import retrofit2.Call;
import retrofit2.http.Body;
import retrofit2.http.POST;

public interface ApiService {

    @POST("/api/speed/update")
    Call<Void> sendSpeed(@Body SpeedRequest request);
}
