;; Documentation Assistance Contract
;; Manages visa applications and legal paperwork

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-INSUFFICIENT-FUNDS (err u102))
(define-constant ERR-APPLICATION-NOT-FOUND (err u103))
(define-constant ERR-INVALID-STATUS (err u104))
(define-constant ERR-ALREADY-EXISTS (err u105))

;; Data Variables
(define-data-var next-application-id uint u1)
(define-data-var service-fee uint u1000000) ;; 1 STX in microSTX
(define-data-var contract-paused bool false)

;; Data Maps
(define-map applications
  { application-id: uint }
  {
    applicant: principal,
    document-type: (string-ascii 50),
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint,
    assigned-officer: (optional principal),
    fee-paid: uint,
    documents-hash: (string-ascii 64)
  }
)

(define-map user-applications
  { user: principal }
  { application-ids: (list 100 uint) }
)

(define-map authorized-officers
  { officer: principal }
  {
    active: bool,
    specialization: (string-ascii 50),
    rating: uint,
    cases-handled: uint
  }
)

(define-map application-documents
  { application-id: uint, document-index: uint }
  {
    document-name: (string-ascii 100),
    document-hash: (string-ascii 64),
    verified: bool,
    uploaded-at: uint
  }
)

;; Private Functions
(define-private (is-authorized-officer (officer principal))
  (match (map-get? authorized-officers { officer: officer })
    officer-data (get active officer-data)
    false
  )
)

(define-private (get-next-application-id)
  (let ((current-id (var-get next-application-id)))
    (var-set next-application-id (+ current-id u1))
    current-id
  )
)

;; Public Functions

;; Submit new visa application
(define-public (submit-application (document-type (string-ascii 50)) (documents-hash (string-ascii 64)))
  (let (
    (application-id (get-next-application-id))
    (current-block-height block-height)
  )
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len document-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len documents-hash) u0) ERR-INVALID-INPUT)

    ;; Transfer service fee
    (try! (stx-transfer? (var-get service-fee) tx-sender CONTRACT-OWNER))

    ;; Create application record
    (map-set applications
      { application-id: application-id }
      {
        applicant: tx-sender,
        document-type: document-type,
        status: "submitted",
        created-at: current-block-height,
        updated-at: current-block-height,
        assigned-officer: none,
        fee-paid: (var-get service-fee),
        documents-hash: documents-hash
      }
    )

    ;; Update user applications list
    (let ((current-apps (default-to { application-ids: (list) }
                                   (map-get? user-applications { user: tx-sender }))))
      (map-set user-applications
        { user: tx-sender }
        { application-ids: (unwrap! (as-max-len?
                                    (append (get application-ids current-apps) application-id)
                                    u100)
                                   ERR-INVALID-INPUT) }
      )
    )

    (ok application-id)
  )
)

;; Assign officer to application
(define-public (assign-officer (application-id uint) (officer principal))
  (let ((application (unwrap! (map-get? applications { application-id: application-id }) ERR-APPLICATION-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-authorized-officer officer) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status application) "submitted") ERR-INVALID-STATUS)

    (map-set applications
      { application-id: application-id }
      (merge application {
        assigned-officer: (some officer),
        status: "in-review",
        updated-at: block-height
      })
    )

    (ok true)
  )
)

;; Update application status
(define-public (update-status (application-id uint) (new-status (string-ascii 20)))
  (let ((application (unwrap! (map-get? applications { application-id: application-id }) ERR-APPLICATION-NOT-FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq (some tx-sender) (get assigned-officer application))) ERR-NOT-AUTHORIZED)
    (asserts! (> (len new-status) u0) ERR-INVALID-INPUT)

    (map-set applications
      { application-id: application-id }
      (merge application {
        status: new-status,
        updated-at: block-height
      })
    )

    (ok true)
  )
)

;; Add authorized officer
(define-public (add-officer (officer principal) (specialization (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len specialization) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? authorized-officers { officer: officer })) ERR-ALREADY-EXISTS)

    (map-set authorized-officers
      { officer: officer }
      {
        active: true,
        specialization: specialization,
        rating: u5,
        cases-handled: u0
      }
    )

    (ok true)
  )
)

;; Upload document for application
(define-public (upload-document (application-id uint) (document-index uint)
                               (document-name (string-ascii 100)) (document-hash (string-ascii 64)))
  (let ((application (unwrap! (map-get? applications { application-id: application-id }) ERR-APPLICATION-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get applicant application)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len document-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len document-hash) u0) ERR-INVALID-INPUT)

    (map-set application-documents
      { application-id: application-id, document-index: document-index }
      {
        document-name: document-name,
        document-hash: document-hash,
        verified: false,
        uploaded-at: block-height
      }
    )

    (ok true)
  )
)

;; Verify document
(define-public (verify-document (application-id uint) (document-index uint))
  (let (
    (application (unwrap! (map-get? applications { application-id: application-id }) ERR-APPLICATION-NOT-FOUND))
    (document (unwrap! (map-get? application-documents { application-id: application-id, document-index: document-index }) ERR-INVALID-INPUT))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq (some tx-sender) (get assigned-officer application))) ERR-NOT-AUTHORIZED)

    (map-set application-documents
      { application-id: application-id, document-index: document-index }
      (merge document { verified: true })
    )

    (ok true)
  )
)

;; Update service fee
(define-public (update-service-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-fee u0) ERR-INVALID-INPUT)

    (var-set service-fee new-fee)
    (ok true)
  )
)

;; Emergency pause
(define-public (toggle-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok (var-get contract-paused))
  )
)

;; Read-only Functions

;; Get application details
(define-read-only (get-application (application-id uint))
  (map-get? applications { application-id: application-id })
)

;; Get user applications
(define-read-only (get-user-applications (user principal))
  (map-get? user-applications { user: user })
)

;; Get officer info
(define-read-only (get-officer-info (officer principal))
  (map-get? authorized-officers { officer: officer })
)

;; Get document info
(define-read-only (get-document (application-id uint) (document-index uint))
  (map-get? application-documents { application-id: application-id, document-index: document-index })
)

;; Get service fee
(define-read-only (get-service-fee)
  (var-get service-fee)
)

;; Get contract status
(define-read-only (is-paused)
  (var-get contract-paused)
)
