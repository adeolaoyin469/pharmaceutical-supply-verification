
;; title: drug-tracker
;; version: 1.0.0
;; summary: Pharmaceutical supply chain tracking system
;; description: Smart contract for tracking pharmaceutical products through the supply chain,
;;              managing distribution, monitoring expiry dates, and handling recalls

;; traits
;; None for this contract

;; token definitions
;; None for this contract

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-DRUG-NOT-FOUND (err u201))
(define-constant ERR-INVALID-LOCATION (err u202))
(define-constant ERR-EXPIRED-DRUG (err u203))
(define-constant ERR-ALREADY-DELIVERED (err u204))
(define-constant ERR-INVALID-STATUS (err u205))
(define-constant ERR-RECALL-ACTIVE (err u206))
(define-constant ERR-TEMPERATURE-VIOLATION (err u207))
(define-constant ERR-INVALID-INPUT (err u208))
(define-constant ERR-SHIPMENT-NOT-FOUND (err u209))
(define-constant ERR-ACCESS-DENIED (err u210))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-TEMP u25) ;; Maximum temperature in Celsius
(define-constant MIN-TEMP u2)  ;; Minimum temperature in Celsius
(define-constant COLD-CHAIN-ALERT-TEMP u8) ;; Alert temperature
(define-constant MAX-MOVEMENT-HISTORY u50)

;; Status constants
(define-constant STATUS-MANUFACTURED "manufactured")
(define-constant STATUS-IN-TRANSIT "in-transit")
(define-constant STATUS-DELIVERED "delivered")
(define-constant STATUS-RECALLED "recalled")
(define-constant STATUS-EXPIRED "expired")
(define-constant STATUS-DISPENSED "dispensed")

;; data vars
(define-data-var next-drug-id uint u1)
(define-data-var next-shipment-id uint u1)
(define-data-var next-movement-id uint u1)
(define-data-var emergency-recall bool false)
(define-data-var total-drugs-tracked uint u0)
(define-data-var total-shipments uint u0)
(define-data-var cold-chain-violations uint u0)

;; data maps
(define-map drugs
  { drug-id: uint }
  {
    name: (string-ascii 100),
    batch-number: (string-ascii 50),
    manufacturer: principal,
    manufacture-date: uint,
    expiry-date: uint,
    quantity: uint,
    unit: (string-ascii 20),
    current-location: (string-ascii 100),
    status: (string-ascii 20),
    requires-cold-chain: bool,
    current-temperature: uint,
    created-at: uint,
    last-updated: uint
  }
)

(define-map shipments
  { shipment-id: uint }
  {
    drug-id: uint,
    from-location: (string-ascii 100),
    to-location: (string-ascii 100),
    carrier: principal,
    shipped-date: uint,
    expected-delivery: uint,
    actual-delivery: (optional uint),
    status: (string-ascii 20),
    temperature-log: (list 20 uint),
    tracking-number: (string-ascii 50),
    notes: (string-ascii 200)
  }
)

(define-map movements
  { movement-id: uint }
  {
    drug-id: uint,
    from-location: (string-ascii 100),
    to-location: (string-ascii 100),
    moved-by: principal,
    timestamp: uint,
    temperature: uint,
    reason: (string-ascii 100),
    verified: bool
  }
)

(define-map locations
  { location-id: (string-ascii 100) }
  {
    name: (string-ascii 100),
    location-type: (string-ascii 50), ;; "warehouse", "pharmacy", "hospital", "distributor"
    address: (string-ascii 200),
    authorized-personnel: (list 10 principal),
    cold-storage-capable: bool,
    active: bool,
    registered-date: uint
  }
)

(define-map recalls
  { recall-id: (string-ascii 50) }
  {
    drug-id: uint,
    batch-numbers: (list 20 (string-ascii 50)),
    recall-reason: (string-ascii 200),
    severity-level: uint, ;; 1-5 (5 being most severe)
    issued-date: uint,
    issuing-authority: principal,
    status: (string-ascii 20), ;; "active", "completed", "cancelled"
    affected-locations: (list 50 (string-ascii 100))
  }
)

(define-map authorized-entities
  { entity: principal }
  {
    entity-type: (string-ascii 50),
    permissions: (list 10 (string-ascii 50)),
    active: bool,
    authorized-by: principal,
    authorization-date: uint
  }
)

(define-map temperature-alerts
  { alert-id: uint }
  {
    drug-id: uint,
    location: (string-ascii 100),
    temperature: uint,
    timestamp: uint,
    severity: (string-ascii 20),
    acknowledged: bool,
    resolved: bool
  }
)

;; public functions

;; Register a new location
(define-public (register-location
  (location-id (string-ascii 100))
  (name (string-ascii 100))
  (location-type (string-ascii 50))
  (address (string-ascii 200))
  (cold-storage-capable bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len location-id) u0) ERR-INVALID-INPUT)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    
    (map-set locations
      { location-id: location-id }
      {
        name: name,
        location-type: location-type,
        address: address,
        authorized-personnel: (list),
        cold-storage-capable: cold-storage-capable,
        active: true,
        registered-date: block-height
      }
    )
    (ok true)
  )
)

;; Register a new drug for tracking
(define-public (register-drug
  (name (string-ascii 100))
  (batch-number (string-ascii 50))
  (manufacture-date uint)
  (expiry-date uint)
  (quantity uint)
  (unit (string-ascii 20))
  (initial-location (string-ascii 100))
  (requires-cold-chain bool))
  (let (
    (drug-id (var-get next-drug-id))
  )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> quantity u0) ERR-INVALID-INPUT)
    (asserts! (> expiry-date block-height) ERR-INVALID-INPUT)
    (asserts! (is-some (map-get? locations { location-id: initial-location })) ERR-INVALID-LOCATION)
    
    (map-set drugs
      { drug-id: drug-id }
      {
        name: name,
        batch-number: batch-number,
        manufacturer: tx-sender,
        manufacture-date: manufacture-date,
        expiry-date: expiry-date,
        quantity: quantity,
        unit: unit,
        current-location: initial-location,
        status: STATUS-MANUFACTURED,
        requires-cold-chain: requires-cold-chain,
        current-temperature: u20, ;; Default room temperature
        created-at: block-height,
        last-updated: block-height
      }
    )
    
    (var-set next-drug-id (+ drug-id u1))
    (var-set total-drugs-tracked (+ (var-get total-drugs-tracked) u1))
    (ok drug-id)
  )
)

;; Track drug movement from one location to another
(define-public (track-movement
  (drug-id uint)
  (from-location (string-ascii 100))
  (to-location (string-ascii 100))
  (temperature uint)
  (reason (string-ascii 100)))
  (let (
    (drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR-DRUG-NOT-FOUND))
    (movement-id (var-get next-movement-id))
  )
    (asserts! (is-some (map-get? locations { location-id: from-location })) ERR-INVALID-LOCATION)
    (asserts! (is-some (map-get? locations { location-id: to-location })) ERR-INVALID-LOCATION)
    (asserts! (is-eq (get current-location drug-data) from-location) ERR-INVALID-LOCATION)
    (asserts! (not (is-eq (get status drug-data) STATUS-RECALLED)) ERR-RECALL-ACTIVE)
    (asserts! (< block-height (get expiry-date drug-data)) ERR-EXPIRED-DRUG)
    
    ;; Check temperature violation for cold-chain drugs
    (unwrap-panic (if (get requires-cold-chain drug-data)
      (begin
        (asserts! (and (>= temperature MIN-TEMP) (<= temperature MAX-TEMP)) ERR-TEMPERATURE-VIOLATION)
        (if (> temperature COLD-CHAIN-ALERT-TEMP)
          (begin
            (unwrap-panic (create-temperature-alert drug-id to-location temperature))
            (ok true)
          )
          (ok true)
        )
      )
      (ok true)
    ))
    
    ;; Record the movement
    (map-set movements
      { movement-id: movement-id }
      {
        drug-id: drug-id,
        from-location: from-location,
        to-location: to-location,
        moved-by: tx-sender,
        timestamp: block-height,
        temperature: temperature,
        reason: reason,
        verified: true
      }
    )
    
    ;; Update drug location and status
    (map-set drugs
      { drug-id: drug-id }
      (merge drug-data {
        current-location: to-location,
        status: STATUS-IN-TRANSIT,
        current-temperature: temperature,
        last-updated: block-height
      })
    )
    
    (var-set next-movement-id (+ movement-id u1))
    (ok movement-id)
  )
)

;; Create a shipment record
(define-public (create-shipment
  (drug-id uint)
  (from-location (string-ascii 100))
  (to-location (string-ascii 100))
  (carrier principal)
  (expected-delivery uint)
  (tracking-number (string-ascii 50)))
  (let (
    (shipment-id (var-get next-shipment-id))
    (drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR-DRUG-NOT-FOUND))
  )
    (asserts! (is-some (map-get? locations { location-id: from-location })) ERR-INVALID-LOCATION)
    (asserts! (is-some (map-get? locations { location-id: to-location })) ERR-INVALID-LOCATION)
    (asserts! (> expected-delivery block-height) ERR-INVALID-INPUT)
    
    (map-set shipments
      { shipment-id: shipment-id }
      {
        drug-id: drug-id,
        from-location: from-location,
        to-location: to-location,
        carrier: carrier,
        shipped-date: block-height,
        expected-delivery: expected-delivery,
        actual-delivery: none,
        status: STATUS-IN-TRANSIT,
        temperature-log: (list),
        tracking-number: tracking-number,
        notes: ""
      }
    )
    
    (var-set next-shipment-id (+ shipment-id u1))
    (var-set total-shipments (+ (var-get total-shipments) u1))
    (ok shipment-id)
  )
)

;; Complete delivery of a shipment
(define-public (complete-delivery (shipment-id uint))
  (let (
    (shipment-data (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR-SHIPMENT-NOT-FOUND))
    (drug-data (unwrap! (map-get? drugs { drug-id: (get drug-id shipment-data) }) ERR-DRUG-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get carrier shipment-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status shipment-data) STATUS-IN-TRANSIT) ERR-ALREADY-DELIVERED)
    
    ;; Update shipment status
    (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment-data {
        actual-delivery: (some block-height),
        status: STATUS-DELIVERED
      })
    )
    
    ;; Update drug status and location
    (map-set drugs
      { drug-id: (get drug-id shipment-data) }
      (merge drug-data {
        current-location: (get to-location shipment-data),
        status: STATUS-DELIVERED,
        last-updated: block-height
      })
    )
    
    (ok true)
  )
)

;; Issue a drug recall
(define-public (issue-recall
  (recall-id (string-ascii 50))
  (drug-id uint)
  (batch-numbers (list 20 (string-ascii 50)))
  (recall-reason (string-ascii 200))
  (severity-level uint))
  (let (
    (drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR-DRUG-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len recall-reason) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= severity-level u1) (<= severity-level u5)) ERR-INVALID-INPUT)
    
    (map-set recalls
      { recall-id: recall-id }
      {
        drug-id: drug-id,
        batch-numbers: batch-numbers,
        recall-reason: recall-reason,
        severity-level: severity-level,
        issued-date: block-height,
        issuing-authority: tx-sender,
        status: "active",
        affected-locations: (list)
      }
    )
    
    ;; Update drug status
    (map-set drugs
      { drug-id: drug-id }
      (merge drug-data {
        status: STATUS-RECALLED,
        last-updated: block-height
      })
    )
    
    (var-set emergency-recall true)
    (ok true)
  )
)

;; Update drug temperature (for cold-chain monitoring)
(define-public (update-temperature (drug-id uint) (temperature uint) (location (string-ascii 100)))
  (let (
    (drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR-DRUG-NOT-FOUND))
  )
    (asserts! (is-eq (get current-location drug-data) location) ERR-INVALID-LOCATION)
    
    ;; Check for temperature violations
    (unwrap-panic (if (get requires-cold-chain drug-data)
      (begin
        (if (or (< temperature MIN-TEMP) (> temperature MAX-TEMP))
          (begin
            (unwrap-panic (create-temperature-alert drug-id location temperature))
            (var-set cold-chain-violations (+ (var-get cold-chain-violations) u1))
            (ok true)
          )
          (ok true)
        )
      )
      (ok true)
    ))
    
    (map-set drugs
      { drug-id: drug-id }
      (merge drug-data {
        current-temperature: temperature,
        last-updated: block-height
      })
    )
    
    (ok true)
  )
)

;; Batch update multiple drug temperatures
(define-public (batch-update-temperatures (updates (list 20 { drug-id: uint, temperature: uint, location: (string-ascii 100) })))
  (let (
    (results (map update-single-temperature updates))
  )
    (ok results)
  )
)

;; Mark drug as expired
(define-public (mark-expired (drug-id uint))
  (let (
    (drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR-DRUG-NOT-FOUND))
  )
    (asserts! (>= block-height (get expiry-date drug-data)) ERR-INVALID-INPUT)
    
    (map-set drugs
      { drug-id: drug-id }
      (merge drug-data {
        status: STATUS-EXPIRED,
        last-updated: block-height
      })
    )
    (ok true)
  )
)

;; read only functions

;; Get drug details
(define-read-only (get-drug (drug-id uint))
  (map-get? drugs { drug-id: drug-id })
)

;; Get shipment details
(define-read-only (get-shipment (shipment-id uint))
  (map-get? shipments { shipment-id: shipment-id })
)

;; Get location details
(define-read-only (get-location (location-id (string-ascii 100)))
  (map-get? locations { location-id: location-id })
)

;; Get recall information
(define-read-only (get-recall (recall-id (string-ascii 50)))
  (map-get? recalls { recall-id: recall-id })
)

;; Get drug movement history (simplified implementation)
(define-read-only (get-movement-history (drug-id uint))
  ;; In a real implementation, this would query movement records for the drug
  ;; For now, return empty list as placeholder
  (list)
)

;; Check if drug is expired
(define-read-only (is-expired (drug-id uint))
  (match (map-get? drugs { drug-id: drug-id })
    drug-data (>= block-height (get expiry-date drug-data))
    false
  )
)

;; Get tracking statistics
(define-read-only (get-tracking-stats)
  {
    total-drugs-tracked: (var-get total-drugs-tracked),
    total-shipments: (var-get total-shipments),
    cold-chain-violations: (var-get cold-chain-violations),
    emergency-recall-active: (var-get emergency-recall),
    next-drug-id: (var-get next-drug-id),
    next-shipment-id: (var-get next-shipment-id)
  }
)

;; Get drugs by location (simplified implementation)
(define-read-only (get-drugs-at-location (location (string-ascii 100)))
  ;; In a real implementation, this would query drug records by location
  ;; For now, return empty list as placeholder
  (list)
)

;; Check cold chain compliance
(define-read-only (is-cold-chain-compliant (drug-id uint))
  (match (map-get? drugs { drug-id: drug-id })
    drug-data
      (if (get requires-cold-chain drug-data)
        (and 
          (>= (get current-temperature drug-data) MIN-TEMP)
          (<= (get current-temperature drug-data) MAX-TEMP)
        )
        true
      )
    false
  )
)

;; Get expired drugs (simplified implementation)
(define-read-only (get-expired-drugs)
  ;; In a real implementation, this would query all expired drug records
  ;; For now, return empty list as placeholder
  (list)
)

;; private functions

;; Create temperature alert
(define-private (create-temperature-alert (drug-id uint) (location (string-ascii 100)) (temperature uint))
  (let (
    (alert-id (var-get next-movement-id)) ;; Reuse counter for simplicity
    (severity (if (> temperature u30) "critical" "warning"))
  )
    (map-set temperature-alerts
      { alert-id: alert-id }
      {
        drug-id: drug-id,
        location: location,
        temperature: temperature,
        timestamp: block-height,
        severity: severity,
        acknowledged: false,
        resolved: false
      }
    )
    (ok alert-id)
  )
)

;; Update single temperature (helper for batch updates)
(define-private (update-single-temperature (update { drug-id: uint, temperature: uint, location: (string-ascii 100) }))
  (update-temperature (get drug-id update) (get temperature update) (get location update))
)

;; Helper function to get all drugs (simplified for demonstration)
(define-private (get-all-drugs)
  ;; In a real implementation, this would iterate through all drug records
  ;; For now, return empty list as placeholder
  (list)
)

;; Helper function to get all movements (simplified for demonstration)
(define-private (get-all-movements)
  ;; In a real implementation, this would iterate through all movement records
  ;; For now, return empty list as placeholder
  (list)
)

