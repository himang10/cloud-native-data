package com.example.consumer.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * 웹 UI 컨트롤러
 *
 * Thymeleaf 템플릿 index.html을 서빙합니다.
 */
@Controller
public class WebController {

    @GetMapping("/")
    public String index() {
        return "index";
    }
}
