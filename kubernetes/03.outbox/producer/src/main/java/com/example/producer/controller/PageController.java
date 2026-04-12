package com.example.producer.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * Thymeleaf 페이지 컨트롤러
 * REST API('/api/**')와 별도로 UI 페이지 제공
 */
@Controller
public class PageController {

    @GetMapping({"/", "/ui"})
    public String index() {
        return "index";
    }
}
