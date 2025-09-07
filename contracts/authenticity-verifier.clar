
;; title: authenticity-verifier
;; version: 1.0.0
;; summary: Pharmaceutical authenticity verification system
;; description: Smart contract for verifying pharmaceutical product authenticity,
;;              managing certificates, and ensuring regulatory compliance

;; traits
;; None for this contract

;; token definitions
;; None for this contract

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PRODUCT-NOT-FOUND (err u101))
(define-constant ERR-INVALID-CERTIFICATE (err u102))
(define-constant ERR-EXPIRED-CERTIFICATE (err u103))
(define-constant ERR-MANUFACTURER-NOT-VERIFIED (err u104))
(define-constant ERR-BATCH-NOT-FOUND (err u105))
(define-constant ERR-ALREADY-EXISTS (err u106))
(define-constant ERR-INVALID-INPUT (err u107))
(define-constant ERR-CERTIFICATE-REVOKED (err u108))
(define-constant ERR-QUALITY-FAILED (err u109))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-CERTIFICATE-VALIDITY u8760) ;; 1 year in hours
(define-constant MIN-QC-SCORE u70) ;; Minimum quality control score

;; data vars
(define-data-var next-product-id uint u1)
(define-data-var next-certificate-id uint u1)
(define-data-var next-batch-id uint u1)
(define-data-var emergency-stop bool false)
(define-data-var total-verified-products uint u0)
(define-data-var total-certificates-issued uint u0)

;; data maps
(define-map products
  { product-id: uint }
  {
    name: (string-ascii 100),
    manufacturer: principal,
    batch-number: (string-ascii 50),
    manufacturing-date: uint,
    expiry-date: uint,
    certificate-id: uint,
    verified: bool,
    quality-score: uint,
    regulatory-approval: (string-ascii 50),
    created-at: uint,
    created-by: principal
  }
)

(define-map certificates
  { certificate-id: uint }
  {
    issuer: principal,
    product-id: uint,
    certificate-type: (string-ascii 50),
    issued-date: uint,
    expiry-date: uint,
    certificate-hash: (buff 32),
    status: (string-ascii 20), ;; "active", "expired", "revoked"
    regulatory-body: (string-ascii 100),
    compliance-data: (string-ascii 200)
  }
)

(define-map manufacturers
  { manufacturer: principal }
  {
    name: (string-ascii 100),
    license-number: (string-ascii 50),
    verified: bool,
    registration-date: uint,
    compliance-score: uint,
    total-products: uint,
    active: bool
  }
)

(define-map batches
  { batch-id: uint }
  {
    batch-number: (string-ascii 50),
    manufacturer: principal,
    production-date: uint,
    quantity: uint,
    quality-tests: (list 10 uint), ;; List of test scores
    average-quality: uint,
    certified: bool,
    products-count: uint
  }
)

(define-map regulatory-approvals
  { approval-id: (string-ascii 50) }
  {
    product-name: (string-ascii 100),
    manufacturer: principal,
    approval-date: uint,
    expiry-date: uint,
    regulatory-body: (string-ascii 50),
    active: bool
  }
)

(define-map authorizations
  { user: principal }
  { role: (string-ascii 20), authorized: bool }
)

(define-map audit-trail
  { event-id: uint }
  {
    action: (string-ascii 50),
    performer: principal,
    target-id: uint,
    timestamp: uint,
    details: (string-ascii 200)
  }
)

;; public functions

;; Register a new manufacturer
(define-public (register-manufacturer 
  (manufacturer principal)
  (name (string-ascii 100))
  (license-number (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? manufacturers { manufacturer: manufacturer })) ERR-ALREADY-EXISTS)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len license-number) u0) ERR-INVALID-INPUT)
    
    (map-set manufacturers
      { manufacturer: manufacturer }
      {
        name: name,
        license-number: license-number,
        verified: false,
        registration-date: block-height,
        compliance-score: u0,
        total-products: u0,
        active: true
      }
    )
    (ok true)
  )
)

;; Verify a manufacturer
(define-public (verify-manufacturer (manufacturer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (let ((manufacturer-data (unwrap! (map-get? manufacturers { manufacturer: manufacturer }) ERR-MANUFACTURER-NOT-VERIFIED)))
      (map-set manufacturers
        { manufacturer: manufacturer }
        (merge manufacturer-data { verified: true })
      )
    )
    (ok true)
  )
)

;; Create a new product batch
(define-public (create-batch
  (batch-number (string-ascii 50))
  (quantity uint)
  (quality-tests (list 10 uint)))
  (let (
    (batch-id (var-get next-batch-id))
    (manufacturer-data (unwrap! (map-get? manufacturers { manufacturer: tx-sender }) ERR-MANUFACTURER-NOT-VERIFIED))
    (average-quality (calculate-average quality-tests))
  )
    (asserts! (get verified manufacturer-data) ERR-MANUFACTURER-NOT-VERIFIED)
    (asserts! (> quantity u0) ERR-INVALID-INPUT)
    (asserts! (>= average-quality MIN-QC-SCORE) ERR-QUALITY-FAILED)
    
    (map-set batches
      { batch-id: batch-id }
      {
        batch-number: batch-number,
        manufacturer: tx-sender,
        production-date: block-height,
        quantity: quantity,
        quality-tests: quality-tests,
        average-quality: average-quality,
        certified: false,
        products-count: u0
      }
    )
    
    (var-set next-batch-id (+ batch-id u1))
    (ok batch-id)
  )
)

;; Issue a certificate for a product
(define-public (issue-certificate
  (product-id uint)
  (certificate-type (string-ascii 50))
  (certificate-hash (buff 32))
  (regulatory-body (string-ascii 100))
  (compliance-data (string-ascii 200)))
  (let (
    (certificate-id (var-get next-certificate-id))
    (product-data (unwrap! (map-get? products { product-id: product-id }) ERR-PRODUCT-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len certificate-type) u0) ERR-INVALID-INPUT)
    
    (map-set certificates
      { certificate-id: certificate-id }
      {
        issuer: tx-sender,
        product-id: product-id,
        certificate-type: certificate-type,
        issued-date: block-height,
        expiry-date: (+ block-height MAX-CERTIFICATE-VALIDITY),
        certificate-hash: certificate-hash,
        status: "active",
        regulatory-body: regulatory-body,
        compliance-data: compliance-data
      }
    )
    
    ;; Update product with certificate
    (map-set products
      { product-id: product-id }
      (merge product-data { certificate-id: certificate-id, verified: true })
    )
    
    (var-set next-certificate-id (+ certificate-id u1))
    (var-set total-certificates-issued (+ (var-get total-certificates-issued) u1))
    (ok certificate-id)
  )
)

;; Register a new pharmaceutical product
(define-public (register-product
  (name (string-ascii 100))
  (batch-number (string-ascii 50))
  (expiry-date uint)
  (quality-score uint)
  (regulatory-approval (string-ascii 50)))
  (let (
    (product-id (var-get next-product-id))
    (manufacturer-data (unwrap! (map-get? manufacturers { manufacturer: tx-sender }) ERR-MANUFACTURER-NOT-VERIFIED))
  )
    (asserts! (get verified manufacturer-data) ERR-MANUFACTURER-NOT-VERIFIED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> expiry-date block-height) ERR-INVALID-INPUT)
    (asserts! (>= quality-score MIN-QC-SCORE) ERR-QUALITY-FAILED)
    
    (map-set products
      { product-id: product-id }
      {
        name: name,
        manufacturer: tx-sender,
        batch-number: batch-number,
        manufacturing-date: block-height,
        expiry-date: expiry-date,
        certificate-id: u0,
        verified: false,
        quality-score: quality-score,
        regulatory-approval: regulatory-approval,
        created-at: block-height,
        created-by: tx-sender
      }
    )
    
    ;; Update manufacturer stats
    (map-set manufacturers
      { manufacturer: tx-sender }
      (merge manufacturer-data { total-products: (+ (get total-products manufacturer-data) u1) })
    )
    
    (var-set next-product-id (+ product-id u1))
    (var-set total-verified-products (+ (var-get total-verified-products) u1))
    (ok product-id)
  )
)

;; Verify product authenticity
(define-public (verify-product
  (product-id uint)
  (batch-number (string-ascii 50))
  (manufacturer principal))
  (let (
    (product-data (unwrap! (map-get? products { product-id: product-id }) ERR-PRODUCT-NOT-FOUND))
    (certificate-data (map-get? certificates { certificate-id: (get certificate-id product-data) }))
  )
    (asserts! (is-eq (get batch-number product-data) batch-number) ERR-INVALID-INPUT)
    (asserts! (is-eq (get manufacturer product-data) manufacturer) ERR-MANUFACTURER-NOT-VERIFIED)
    (asserts! (< block-height (get expiry-date product-data)) ERR-EXPIRED-CERTIFICATE)
    
    ;; Check certificate if exists
    (match certificate-data
      cert-data (begin
        (asserts! (is-eq (get status cert-data) "active") ERR-CERTIFICATE-REVOKED)
        (asserts! (< block-height (get expiry-date cert-data)) ERR-EXPIRED-CERTIFICATE)
        (ok { verified: true, certificate-valid: true })
      )
      (ok { verified: (get verified product-data), certificate-valid: false })
    )
  )
)

;; Revoke a certificate
(define-public (revoke-certificate (certificate-id uint))
  (let (
    (certificate-data (unwrap! (map-get? certificates { certificate-id: certificate-id }) ERR-INVALID-CERTIFICATE))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status certificate-data) "active") ERR-CERTIFICATE-REVOKED)
    
    (map-set certificates
      { certificate-id: certificate-id }
      (merge certificate-data { status: "revoked" })
    )
    (ok true)
  )
)

;; Batch verification for multiple products
(define-public (batch-verify-products (product-ids (list 50 uint)))
  (let (
    (results (map verify-single-product product-ids))
  )
    (ok results)
  )
)

;; Emergency stop functionality
(define-public (emergency-stop-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set emergency-stop true)
    (ok true)
  )
)

;; read only functions

;; Get product details
(define-read-only (get-product (product-id uint))
  (map-get? products { product-id: product-id })
)

;; Get certificate details
(define-read-only (get-certificate (certificate-id uint))
  (map-get? certificates { certificate-id: certificate-id })
)

;; Get manufacturer details
(define-read-only (get-manufacturer (manufacturer principal))
  (map-get? manufacturers { manufacturer: manufacturer })
)

;; Get batch details
(define-read-only (get-batch (batch-id uint))
  (map-get? batches { batch-id: batch-id })
)

;; Check if product is authentic
(define-read-only (is-authentic (product-id uint))
  (match (map-get? products { product-id: product-id })
    product-data
      (let (
        (certificate-data (map-get? certificates { certificate-id: (get certificate-id product-data) }))
      )
        (and 
          (get verified product-data)
          (< block-height (get expiry-date product-data))
          (match certificate-data
            cert-data (and 
              (is-eq (get status cert-data) "active")
              (< block-height (get expiry-date cert-data))
            )
            false
          )
        )
      )
    false
  )
)

;; Get verification statistics
(define-read-only (get-verification-stats)
  {
    total-verified-products: (var-get total-verified-products),
    total-certificates-issued: (var-get total-certificates-issued),
    next-product-id: (var-get next-product-id),
    next-certificate-id: (var-get next-certificate-id),
    emergency-stop-active: (var-get emergency-stop)
  }
)

;; Check manufacturer verification status
(define-read-only (is-manufacturer-verified (manufacturer principal))
  (match (map-get? manufacturers { manufacturer: manufacturer })
    manufacturer-data (and (get verified manufacturer-data) (get active manufacturer-data))
    false
  )
)

;; Get products by manufacturer
(define-read-only (get-manufacturer-stats (manufacturer principal))
  (map-get? manufacturers { manufacturer: manufacturer })
)

;; private functions

;; Calculate average of quality test scores
(define-private (calculate-average (scores (list 10 uint)))
  (let (
    (sum (fold + scores u0))
    (count (len scores))
  )
    (if (> count u0)
      (/ sum count)
      u0
    )
  )
)

;; Verify single product (helper for batch verification)
(define-private (verify-single-product (product-id uint))
  (match (map-get? products { product-id: product-id })
    product-data
      {
        product-id: product-id,
        verified: (get verified product-data),
        authentic: (is-authentic product-id),
        expired: (> block-height (get expiry-date product-data))
      }
    {
      product-id: product-id,
      verified: false,
      authentic: false,
      expired: true
    }
  )
)

