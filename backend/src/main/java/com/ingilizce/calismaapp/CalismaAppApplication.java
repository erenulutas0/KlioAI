package com.ingilizce.calismaapp;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class CalismaAppApplication {

    public static void main(String[] args) {
        SpringApplication.run(CalismaAppApplication.class, args);
    }

}
