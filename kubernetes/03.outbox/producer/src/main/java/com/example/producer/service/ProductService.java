package com.example.producer.service;

import com.example.producer.domain.Product;
import com.example.producer.repository.ProductRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * Product 도메인 서비스
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ProductService {

    private final ProductRepository productRepository;
    private final OutboxService outboxService;

    /**
     * 상품 생성
     */
    @Transactional
    public Product createProduct(Product product) {
        log.info("Creating product: name={}", product.getName());
        
        Product savedProduct = productRepository.save(product);
        
        // Outbox 이벤트 발행
        outboxService.publishEvent(
                savedProduct.getId(),
                "product",
                "created",
                savedProduct
        );
        
        log.info("Product created successfully: id={}, name={}", savedProduct.getId(), savedProduct.getName());
        return savedProduct;
    }

    /**
     * 상품 수정
     */
    @Transactional
    public Product updateProduct(Long id, Product product) {
        log.info("Updating product: id={}", id);
        
        Product existingProduct = productRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Product not found: id=" + id));
        
        existingProduct.setName(product.getName());
        existingProduct.setDescription(product.getDescription());
        existingProduct.setPrice(product.getPrice());
        existingProduct.setStock(product.getStock());
        
        Product updatedProduct = productRepository.save(existingProduct);
        
        // Outbox 이벤트 발행
        outboxService.publishEvent(
                updatedProduct.getId(),
                "product",
                "updated",
                updatedProduct
        );
        
        log.info("Product updated successfully: id={}", updatedProduct.getId());
        return updatedProduct;
    }

    /**
     * 상품 삭제
     */
    @Transactional
    public void deleteProduct(Long id) {
        log.info("Deleting product: id={}", id);
        
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Product not found: id=" + id));
        
        // Outbox 이벤트 발행
        outboxService.publishEvent(
                product.getId(),
                "product",
                "deleted",
                product
        );
        
        productRepository.delete(product);
        log.info("Product deleted successfully: id={}", id);
    }

    /**
     * 상품 조회
     */
    @Transactional(readOnly = true)
    public Product getProduct(Long id) {
        return productRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Product not found: id=" + id));
    }

    /**
     * 전체 상품 조회
     */
    @Transactional(readOnly = true)
    public List<Product> getAllProducts() {
        return productRepository.findAll();
    }
}

