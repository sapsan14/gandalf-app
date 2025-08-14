package com.example.gandalfapp;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.util.StreamUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.time.ZoneId;
import java.time.ZonedDateTime;

@RestController
public class GandalfController {

    private final Counter gandalfCounter;
    private final Counter colomboCounter;

    public GandalfController(MeterRegistry registry) {
        this.gandalfCounter = registry.counter("gandalf_requests_total");
        this.colomboCounter = registry.counter("colombo_requests_total");
    }

    @GetMapping(value = "/gandalf", produces = MediaType.IMAGE_JPEG_VALUE)
    public byte[] getGandalf() throws IOException {
        gandalfCounter.increment();
        ClassPathResource imgFile = new ClassPathResource("static/gandalf.png");
        return StreamUtils.copyToByteArray(imgFile.getInputStream());
    }

    @GetMapping("/colombo")
    public String getColomboTime() {
        colomboCounter.increment();
        ZonedDateTime now = ZonedDateTime.now(ZoneId.of("Asia/Colombo"));
        return now.toString();
    }
}
