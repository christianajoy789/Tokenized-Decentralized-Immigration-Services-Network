;; Family Reunification Contract
;; Assists with bringing family members to new countries

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-INPUT (err u501))
(define-constant ERR-INSUFFICIENT-FUNDS (err u502))
(define-constant ERR-CASE-NOT-FOUND (err u503))
(define-constant ERR-ALREADY-EXISTS (err u504))
(define-constant ERR-INVALID-STATUS (err u505))
(define-constant ERR-INVALID-RELATIONSHIP (err u506))

;; Data Variables
(define-data-var next-case-id uint u1)
(define-data-var service-fee uint u2000000) ;; 2 STX
(define-data-var contract-paused bool false)

;; Data Maps
(define-map reunification-cases
  { case-id: uint }
  {
    petitioner: principal,
    case-type: (string-ascii 50),
    priority-level: (string-ascii 20),
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint,
    estimated-completion: uint,
    total-family-members: uint,
    approved-members: uint,
    case-officer: (optional principal),
    fee-paid: uint
  }
)

(define-map family-members
  { case-id: uint, member-index: uint }
  {
    name: (string-ascii 100),
    relationship: (string-ascii 30),
    age: uint,
    country-of-origin: (string-ascii 50),
    status: (string-ascii 20),
    documents-submitted: bool,
    background-check-complete: bool,
    interview-scheduled: bool,
    approval-date: (optional uint)
  }
)

(define-map petitioner-cases
  { petitioner: principal }
  { case-ids: (list 50 uint) }
)

(define-map case-documents
  { case-id: uint, document-type: (string-ascii 50) }
  {
    document-hash: (string-ascii 64),
    submitted-by: principal,
    submitted-at: uint,
    verified: bool,
    verified-by: (optional principal),
    verification-date: (optional uint)
  }
)

(define-map case-timeline
  { case-id: uint, event-index: uint }
  {
    event-type: (string-ascii 50),
    description: (string-ascii 200),
    timestamp: uint,
    updated-by: principal
  }
)

(define-map authorized-officers
  { officer: principal }
  {
    active: bool,
    specialization: (string-ascii 50),
    cases-handled: uint,
    rating: uint
  }
)

(define-map relationship-requirements
  { relationship: (string-ascii 30) }
  {
    required-documents: (list 10 (string-ascii 50)),
    processing-time-weeks: uint,
    priority-multiplier: uint,
    additional-requirements: (string-ascii 200)
  }
)

(define-map case-communications
  { case-id: uint, message-index: uint }
  {
    sender: principal,
    recipient: principal,
    message: (string-ascii 500),
    timestamp: uint,
    message-type: (string-ascii 20)
  }
)

;; Private Functions
(define-private (is-authorized-officer (officer principal))
  (match (map-get? authorized-officers { officer: officer })
    officer-data (get active officer-data)
    false
  )
)

(define-private (get-next-case-id)
  (let ((current-id (var-get next-case-id)))
    (var-set next-case-id (+ current-id u1))
    current-id
  )
)

(define-private (is-valid-relationship (relationship (string-ascii 30)))
  (or (is-eq relationship "spouse")
      (is-eq relationship "child")
      (is-eq relationship "parent")
      (is-eq relationship "sibling")
      (is-eq relationship "grandparent")
      (is-eq relationship "grandchild"))
)

;; Public Functions

;; Create reunification case
(define-public (create-case (case-type (string-ascii 50))
                           (priority-level (string-ascii 20))
                           (total-family-members uint)
                           (estimated-completion uint))
  (let (
    (case-id (get-next-case-id))
    (current-block-height block-height)
  )
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len case-type) u0) ERR-INVALID-INPUT)
    (asserts! (> total-family-members u0) ERR-INVALID-INPUT)
    (asserts! (> estimated-completion current-block-height) ERR-INVALID-INPUT)

    ;; Transfer service fee
    (try! (stx-transfer? (var-get service-fee) tx-sender CONTRACT-OWNER))

    (map-set reunification-cases
      { case-id: case-id }
      {
        petitioner: tx-sender,
        case-type: case-type,
        priority-level: priority-level,
        status: "submitted",
        created-at: current-block-height,
        updated-at: current-block-height,
        estimated-completion: estimated-completion,
        total-family-members: total-family-members,
        approved-members: u0,
        case-officer: none,
        fee-paid: (var-get service-fee)
      }
    )

    ;; Update petitioner cases list
    (let ((current-cases (default-to { case-ids: (list) }
                                    (map-get? petitioner-cases { petitioner: tx-sender }))))
      (map-set petitioner-cases
        { petitioner: tx-sender }
        { case-ids: (unwrap! (as-max-len?
                             (append (get case-ids current-cases) case-id)
                             u50)
                            ERR-INVALID-INPUT) }
      )
    )

    ;; Add initial timeline event
    (map-set case-timeline
      { case-id: case-id, event-index: u1 }
      {
        event-type: "case-created",
        description: "Reunification case submitted for review",
        timestamp: current-block-height,
        updated-by: tx-sender
      }
    )

    (ok case-id)
  )
)

;; Add family member to case
(define-public (add-family-member (case-id uint)
                                 (member-index uint)
                                 (name (string-ascii 100))
                                 (relationship (string-ascii 30))
                                 (age uint)
                                 (country-of-origin (string-ascii 50)))
  (let ((case-data (unwrap! (map-get? reunification-cases { case-id: case-id }) ERR-CASE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get petitioner case-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (is-valid-relationship relationship) ERR-INVALID-RELATIONSHIP)
    (asserts! (> age u0) ERR-INVALID-INPUT)
    (asserts! (> (len country-of-origin) u0) ERR-INVALID-INPUT)

    (map-set family-members
      { case-id: case-id, member-index: member-index }
      {
        name: name,
        relationship: relationship,
        age: age,
        country-of-origin: country-of-origin,
        status: "pending",
        documents-submitted: false,
        background-check-complete: false,
        interview-scheduled: false,
        approval-date: none
      }
    )

    (ok true)
  )
)

;; Submit case document
(define-public (submit-document (case-id uint)
                               (document-type (string-ascii 50))
                               (document-hash (string-ascii 64)))
  (let ((case-data (unwrap! (map-get? reunification-cases { case-id: case-id }) ERR-CASE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get petitioner case-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len document-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len document-hash) u0) ERR-INVALID-INPUT)

    (map-set case-documents
      { case-id: case-id, document-type: document-type }
      {
        document-hash: document-hash,
        submitted-by: tx-sender,
        submitted-at: block-height,
        verified: false,
        verified-by: none,
        verification-date: none
      }
    )

    (ok true)
  )
)

;; Assign case officer
(define-public (assign-officer (case-id uint) (officer principal))
  (let ((case-data (unwrap! (map-get? reunification-cases { case-id: case-id }) ERR-CASE-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-authorized-officer officer) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status case-data) "submitted") ERR-INVALID-STATUS)

    (map-set reunification-cases
      { case-id: case-id }
      (merge case-data {
        case-officer: (some officer),
        status: "under-review",
        updated-at: block-height
      })
    )

    ;; Add timeline event
    (map-set case-timeline
      { case-id: case-id, event-index: u2 }
      {
        event-type: "officer-assigned",
        description: "Case officer assigned for review",
        timestamp: block-height,
        updated-by: tx-sender
      }
    )

    (ok true)
  )
)

;; Verify document
(define-public (verify-document (case-id uint) (document-type (string-ascii 50)))
  (let (
    (case-data (unwrap! (map-get? reunification-cases { case-id: case-id }) ERR-CASE-NOT-FOUND))
    (document-data (unwrap! (map-get? case-documents { case-id: case-id, document-type: document-type }) ERR-INVALID-INPUT))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq (some tx-sender) (get case-officer case-data))) ERR-NOT-AUTHORIZED)

    (map-set case-documents
      { case-id: case-id, document-type: document-type }
      (merge document-data {
        verified: true,
        verified-by: (some tx-sender),
        verification-date: (some block-height)
      })
    )

    (ok true)
  )
)

;; Update family member status
(define-public (update-member-status (case-id uint)
                                    (member-index uint)
                                    (new-status (string-ascii 20))
                                    (documents-submitted bool)
                                    (background-check-complete bool)
                                    (interview-scheduled bool))
  (let (
    (case-data (unwrap! (map-get? reunification-cases { case-id: case-id }) ERR-CASE-NOT-FOUND))
    (member-data (unwrap! (map-get? family-members { case-id: case-id, member-index: member-index }) ERR-INVALID-INPUT))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq (some tx-sender) (get case-officer case-data))) ERR-NOT-AUTHORIZED)
    (asserts! (> (len new-status) u0) ERR-INVALID-INPUT)

    (map-set family-members
      { case-id: case-id, member-index: member-index }
      (merge member-data {
        status: new-status,
        documents-submitted: documents-submitted,
        background-check-complete: background-check-complete,
        interview-scheduled: interview-scheduled,
        approval-date: (if (is-eq new-status "approved") (some block-height) none)
      })
    )

    ;; Update case approved members count if approved
    (if (is-eq new-status "approved")
      (map-set reunification-cases
        { case-id: case-id }
        (merge case-data {
          approved-members: (+ (get approved-members case-data) u1),
          updated-at: block-height
        })
      )
      true
    )

    (ok true)
  )
)

;; Add case communication
(define-public (add-communication (case-id uint)
                                 (message-index uint)
                                 (recipient principal)
                                 (message (string-ascii 500))
                                 (message-type (string-ascii 20)))
  (let ((case-data (unwrap! (map-get? reunification-cases { case-id: case-id }) ERR-CASE-NOT-FOUND)))
    (asserts! (or (is-eq tx-sender (get petitioner case-data))
                  (is-eq (some tx-sender) (get case-officer case-data))
                  (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len message) u0) ERR-INVALID-INPUT)

    (map-set case-communications
      { case-id: case-id, message-index: message-index }
      {
        sender: tx-sender,
        recipient: recipient,
        message: message,
        timestamp: block-height,
        message-type: message-type
      }
    )

    (ok true)
  )
)

;; Set relationship requirements
(define-public (set-relationship-requirements (relationship (string-ascii 30))
                                             (required-documents (list 10 (string-ascii 50)))
                                             (processing-time-weeks uint)
                                             (priority-multiplier uint)
                                             (additional-requirements (string-ascii 200)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-relationship relationship) ERR-INVALID-RELATIONSHIP)
    (asserts! (> processing-time-weeks u0) ERR-INVALID-INPUT)
    (asserts! (> priority-multiplier u0) ERR-INVALID-INPUT)

    (map-set relationship-requirements
      { relationship: relationship }
      {
        required-documents: required-documents,
        processing-time-weeks: processing-time-weeks,
        priority-multiplier: priority-multiplier,
        additional-requirements: additional-requirements
      }
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
        cases-handled: u0,
        rating: u5
      }
    )

    (ok true)
  )
)

;; Update case status
(define-public (update-case-status (case-id uint) (new-status (string-ascii 20)))
  (let ((case-data (unwrap! (map-get? reunification-cases { case-id: case-id }) ERR-CASE-NOT-FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq (some tx-sender) (get case-officer case-data))) ERR-NOT-AUTHORIZED)
    (asserts! (> (len new-status) u0) ERR-INVALID-INPUT)

    (map-set reunification-cases
      { case-id: case-id }
      (merge case-data {
        status: new-status,
        updated-at: block-height
      })
    )

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

;; Get case details
(define-read-only (get-case (case-id uint))
  (map-get? reunification-cases { case-id: case-id })
)

;; Get family member details
(define-read-only (get-family-member (case-id uint) (member-index uint))
  (map-get? family-members { case-id: case-id, member-index: member-index })
)

;; Get petitioner cases
(define-read-only (get-petitioner-cases (petitioner principal))
  (map-get? petitioner-cases { petitioner: petitioner })
)

;; Get case document
(define-read-only (get-document (case-id uint) (document-type (string-ascii 50)))
  (map-get? case-documents { case-id: case-id, document-type: document-type })
)

;; Get timeline event
(define-read-only (get-timeline-event (case-id uint) (event-index uint))
  (map-get? case-timeline { case-id: case-id, event-index: event-index })
)

;; Get officer info
(define-read-only (get-officer-info (officer principal))
  (map-get? authorized-officers { officer: officer })
)

;; Get relationship requirements
(define-read-only (get-relationship-requirements (relationship (string-ascii 30)))
  (map-get? relationship-requirements { relationship: relationship })
)

;; Get communication
(define-read-only (get-communication (case-id uint) (message-index uint))
  (map-get? case-communications { case-id: case-id, message-index: message-index })
)

;; Get service fee
(define-read-only (get-service-fee)
  (var-get service-fee)
)

;; Check if paused
(define-read-only (is-paused)
  (var-get contract-paused)
)
