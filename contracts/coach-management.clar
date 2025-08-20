;; Coach Management Contract
;; Manages coach registration, certification, and credential verification

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-COACH-NOT-FOUND (err u101))
(define-constant ERR-COACH-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-CERTIFICATION (err u103))
(define-constant ERR-CERTIFICATION-EXPIRED (err u104))
(define-constant ERR-INVALID-INPUT (err u105))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-coach-id uint u1)

;; Coach certification levels
(define-constant CERT-BASIC u1)
(define-constant CERT-INTERMEDIATE u2)
(define-constant CERT-ADVANCED u3)
(define-constant CERT-MASTER u4)

;; Coach specializations
(define-constant SPEC-NUTRITION u1)
(define-constant SPEC-FITNESS u2)
(define-constant SPEC-MENTAL-HEALTH u3)
(define-constant SPEC-CHRONIC-DISEASE u4)
(define-constant SPEC-PREVENTIVE-CARE u5)

;; Coach data structure
(define-map coaches
  { coach-id: uint }
  {
    principal: principal,
    name: (string-ascii 100),
    email: (string-ascii 100),
    certification-level: uint,
    specializations: (list 5 uint),
    certification-date: uint,
    certification-expiry: uint,
    is-active: bool,
    total-clients: uint,
    success-rate: uint,
    created-at: uint
  }
)

;; Principal to coach ID mapping
(define-map principal-to-coach-id principal uint)

;; Coach certifications tracking
(define-map coach-certifications
  { coach-id: uint, cert-type: uint }
  {
    issued-date: uint,
    expiry-date: uint,
    issuing-authority: (string-ascii 100),
    certificate-hash: (buff 32),
    is-valid: bool
  }
)

;; Coach performance metrics
(define-map coach-metrics
  { coach-id: uint }
  {
    total-sessions: uint,
    client-satisfaction: uint,
    program-completions: uint,
    health-improvements: uint,
    last-updated: uint
  }
)

;; Read-only functions

;; Get coach by ID
(define-read-only (get-coach (coach-id uint))
  (map-get? coaches { coach-id: coach-id })
)

;; Get coach ID by principal
(define-read-only (get-coach-id-by-principal (coach-principal principal))
  (map-get? principal-to-coach-id coach-principal)
)

;; Get coach certification
(define-read-only (get-coach-certification (coach-id uint) (cert-type uint))
  (map-get? coach-certifications { coach-id: coach-id, cert-type: cert-type })
)

;; Get coach metrics
(define-read-only (get-coach-metrics (coach-id uint))
  (map-get? coach-metrics { coach-id: coach-id })
)

;; Check if coach is active and certified
(define-read-only (is-coach-active (coach-id uint))
  (match (get-coach coach-id)
    coach-data (and
      (get is-active coach-data)
      (> (get certification-expiry coach-data) block-height)
    )
    false
  )
)

;; Validate certification level
(define-read-only (is-valid-certification-level (level uint))
  (and (>= level CERT-BASIC) (<= level CERT-MASTER))
)

;; Validate specialization
(define-read-only (is-valid-specialization (spec uint))
  (and (>= spec SPEC-NUTRITION) (<= spec SPEC-PREVENTIVE-CARE))
)

;; Public functions

;; Register a new coach
(define-public (register-coach
  (name (string-ascii 100))
  (email (string-ascii 100))
  (certification-level uint)
  (specializations (list 5 uint))
  (certification-expiry uint)
)
  (let (
    (coach-id (var-get next-coach-id))
    (caller tx-sender)
  )
    ;; Validate inputs
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len email) u0) ERR-INVALID-INPUT)
    (asserts! (is-valid-certification-level certification-level) ERR-INVALID-CERTIFICATION)
    (asserts! (> certification-expiry block-height) ERR-CERTIFICATION-EXPIRED)
    (asserts! (is-none (get-coach-id-by-principal caller)) ERR-COACH-ALREADY-EXISTS)

    ;; Validate all specializations
    (asserts! (fold validate-specialization-fold specializations true) ERR-INVALID-INPUT)

    ;; Create coach record
    (map-set coaches
      { coach-id: coach-id }
      {
        principal: caller,
        name: name,
        email: email,
        certification-level: certification-level,
        specializations: specializations,
        certification-date: block-height,
        certification-expiry: certification-expiry,
        is-active: true,
        total-clients: u0,
        success-rate: u0,
        created-at: block-height
      }
    )

    ;; Map principal to coach ID
    (map-set principal-to-coach-id caller coach-id)

    ;; Initialize coach metrics
    (map-set coach-metrics
      { coach-id: coach-id }
      {
        total-sessions: u0,
        client-satisfaction: u0,
        program-completions: u0,
        health-improvements: u0,
        last-updated: block-height
      }
    )

    ;; Increment next coach ID
    (var-set next-coach-id (+ coach-id u1))

    (ok coach-id)
  )
)

;; Update coach profile
(define-public (update-coach-profile
  (coach-id uint)
  (name (string-ascii 100))
  (email (string-ascii 100))
  (specializations (list 5 uint))
)
  (let (
    (coach-data (unwrap! (get-coach coach-id) ERR-COACH-NOT-FOUND))
    (caller tx-sender)
  )
    ;; Verify caller is the coach
    (asserts! (is-eq caller (get principal coach-data)) ERR-NOT-AUTHORIZED)

    ;; Validate inputs
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len email) u0) ERR-INVALID-INPUT)
    (asserts! (fold validate-specialization-fold specializations true) ERR-INVALID-INPUT)

    ;; Update coach record
    (map-set coaches
      { coach-id: coach-id }
      (merge coach-data {
        name: name,
        email: email,
        specializations: specializations
      })
    )

    (ok true)
  )
)

;; Add certification to coach
(define-public (add-certification
  (coach-id uint)
  (cert-type uint)
  (expiry-date uint)
  (issuing-authority (string-ascii 100))
  (certificate-hash (buff 32))
)
  (let (
    (coach-data (unwrap! (get-coach coach-id) ERR-COACH-NOT-FOUND))
    (caller tx-sender)
  )
    ;; Only contract owner or the coach can add certifications
    (asserts! (or
      (is-eq caller (var-get contract-owner))
      (is-eq caller (get principal coach-data))
    ) ERR-NOT-AUTHORIZED)

    ;; Validate inputs
    (asserts! (> expiry-date block-height) ERR-CERTIFICATION-EXPIRED)
    (asserts! (> (len issuing-authority) u0) ERR-INVALID-INPUT)

    ;; Add certification
    (map-set coach-certifications
      { coach-id: coach-id, cert-type: cert-type }
      {
        issued-date: block-height,
        expiry-date: expiry-date,
        issuing-authority: issuing-authority,
        certificate-hash: certificate-hash,
        is-valid: true
      }
    )

    (ok true)
  )
)

;; Update coach metrics
(define-public (update-coach-metrics
  (coach-id uint)
  (total-sessions uint)
  (client-satisfaction uint)
  (program-completions uint)
  (health-improvements uint)
)
  (let (
    (coach-data (unwrap! (get-coach coach-id) ERR-COACH-NOT-FOUND))
    (caller tx-sender)
  )
    ;; Only contract owner can update metrics
    (asserts! (is-eq caller (var-get contract-owner)) ERR-NOT-AUTHORIZED)

    ;; Validate satisfaction rating (0-100)
    (asserts! (<= client-satisfaction u100) ERR-INVALID-INPUT)

    ;; Update metrics
    (map-set coach-metrics
      { coach-id: coach-id }
      {
        total-sessions: total-sessions,
        client-satisfaction: client-satisfaction,
        program-completions: program-completions,
        health-improvements: health-improvements,
        last-updated: block-height
      }
    )

    ;; Update success rate in coach record
    (let (
      (success-rate (if (> total-sessions u0)
        (/ (* program-completions u100) total-sessions)
        u0
      ))
    )
      (map-set coaches
        { coach-id: coach-id }
        (merge coach-data {
          success-rate: success-rate
        })
      )
    )

    (ok true)
  )
)

;; Deactivate coach
(define-public (deactivate-coach (coach-id uint))
  (let (
    (coach-data (unwrap! (get-coach coach-id) ERR-COACH-NOT-FOUND))
    (caller tx-sender)
  )
    ;; Only contract owner or the coach can deactivate
    (asserts! (or
      (is-eq caller (var-get contract-owner))
      (is-eq caller (get principal coach-data))
    ) ERR-NOT-AUTHORIZED)

    ;; Deactivate coach
    (map-set coaches
      { coach-id: coach-id }
      (merge coach-data { is-active: false })
    )

    (ok true)
  )
)

;; Reactivate coach
(define-public (reactivate-coach (coach-id uint))
  (let (
    (coach-data (unwrap! (get-coach coach-id) ERR-COACH-NOT-FOUND))
    (caller tx-sender)
  )
    ;; Only contract owner can reactivate
    (asserts! (is-eq caller (var-get contract-owner)) ERR-NOT-AUTHORIZED)

    ;; Check certification is still valid
    (asserts! (> (get certification-expiry coach-data) block-height) ERR-CERTIFICATION-EXPIRED)

    ;; Reactivate coach
    (map-set coaches
      { coach-id: coach-id }
      (merge coach-data { is-active: true })
    )

    (ok true)
  )
)

;; Helper functions

;; Validate specialization in fold
(define-private (validate-specialization-fold (spec uint) (acc bool))
  (and acc (is-valid-specialization spec))
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Get next coach ID
(define-read-only (get-next-coach-id)
  (var-get next-coach-id)
)
