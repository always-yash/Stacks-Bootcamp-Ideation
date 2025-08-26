;; FlightDelay Insurance Contract
;; Automated flight delay compensation using smart contract payouts

;; Define the fungible token for insurance payouts
(define-fungible-token delay-compensation-token)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-flight (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-flight-not-found (err u103))
(define-constant err-already-claimed (err u104))
(define-constant err-flight-not-delayed (err u105))

;; Flight status constants
(define-constant flight-status-on-time u0)
(define-constant flight-status-delayed u1)
(define-constant flight-status-cancelled u2)

;; Compensation rates (in tokens)
(define-constant delay-compensation-rate u100) ;; 100 tokens per delayed flight
(define-constant cancellation-compensation-rate u200) ;; 200 tokens per cancelled flight

;; Flight data structure
(define-map flight-data
  { flight-number: (string-ascii 10), flight-date: (string-ascii 10) }
  {
    passenger: principal,
    status: uint,
    delay-minutes: uint,
    compensation-claimed: bool,
    premium-paid: uint
  })

;; Insurance pool tracking
(define-data-var total-pool uint u0)
(define-data-var total-claims-paid uint u0)

;; Purchase flight delay insurance
(define-public (purchase-insurance (flight-number (string-ascii 10)) (flight-date (string-ascii 10)) (premium uint))
  (begin
    ;; Validate inputs
    (asserts! (> premium u0) (err u106))
    (asserts! (> (len flight-number) u0) (err u107))
    (asserts! (> (len flight-date) u0) (err u108))
    
    ;; Transfer premium from passenger to contract
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    ;; Store flight insurance data
    (map-set flight-data
      { flight-number: flight-number, flight-date: flight-date }
      {
        passenger: tx-sender,
        status: flight-status-on-time,
        delay-minutes: u0,
        compensation-claimed: false,
        premium-paid: premium
      })
    
    ;; Update insurance pool
    (var-set total-pool (+ (var-get total-pool) premium))
    
    ;; Mint compensation tokens to contract for future payouts
    (try! (ft-mint? delay-compensation-token (* premium u2) (as-contract tx-sender)))
    
    (ok true)))

;; Claim compensation for delayed/cancelled flight
(define-public (claim-compensation (flight-number (string-ascii 10)) (flight-date (string-ascii 10)))
  (let (
    (flight-key { flight-number: flight-number, flight-date: flight-date })
    (flight-info (unwrap! (map-get? flight-data flight-key) err-flight-not-found))
  )
    ;; Verify the passenger is claiming their own flight
    (asserts! (is-eq tx-sender (get passenger flight-info)) (err u109))
    
    ;; Check if compensation already claimed
    (asserts! (not (get compensation-claimed flight-info)) err-already-claimed)
    
    ;; Check if flight is delayed or cancelled
    (asserts! (or 
      (is-eq (get status flight-info) flight-status-delayed)
      (is-eq (get status flight-info) flight-status-cancelled)
    ) err-flight-not-delayed)
    
    ;; Calculate compensation amount
    (let (
      (compensation-amount 
        (if (is-eq (get status flight-info) flight-status-cancelled)
          cancellation-compensation-rate
          delay-compensation-rate))
    )
      ;; Transfer compensation tokens to passenger
      (try! (as-contract (ft-transfer? delay-compensation-token compensation-amount tx-sender (get passenger flight-info))))
      
      ;; Mark as claimed
      (map-set flight-data flight-key
        (merge flight-info { compensation-claimed: true }))
      
      ;; Update total claims paid
      (var-set total-claims-paid (+ (var-get total-claims-paid) compensation-amount))
      
      (ok compensation-amount))))

;; Read-only functions for getting information
(define-read-only (get-flight-info (flight-number (string-ascii 10)) (flight-date (string-ascii 10)))
  (map-get? flight-data { flight-number: flight-number, flight-date: flight-date }))

(define-read-only (get-total-pool)
  (var-get total-pool))

(define-read-only (get-total-claims-paid)
  (var-get total-claims-paid))

;; Owner function to update flight status (simulates real-time data feed)
(define-public (update-flight-status (flight-number (string-ascii 10)) (flight-date (string-ascii 10)) (new-status uint) (delay-minutes uint))
  (let (
    (flight-key { flight-number: flight-number, flight-date: flight-date })
    (flight-info (unwrap! (map-get? flight-data flight-key) err-flight-not-found))
  )
    ;; Only contract owner can update flight status (in real implementation, this would be an oracle)
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    ;; Update flight status
    (map-set flight-data flight-key
      (merge flight-info { 
        status: new-status, 
        delay-minutes: delay-minutes 
      }))
    
    (ok true)))