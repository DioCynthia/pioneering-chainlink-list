;; chainlink-learning-tracker
;;
;; A smart contract to manage learning milestones, achievements, and visual tree 
;; structures for the Pioneering Chainlink Learning platform. This contract enables 
;; the creation, verification, and organization of learning milestones in tree-like 
;; structures, creating an immutable record of a learner's educational journey.
;; =============================
;; Constants & Error Codes
;; =============================
(define-constant CONTRACT-OWNER tx-sender)
;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-USER-NOT-FOUND (err u101))
(define-constant ERR-MILESTONE-NOT-FOUND (err u102))
(define-constant ERR-MILESTONE-ALREADY-EXISTS (err u103))
(define-constant ERR-FOREST-NOT-FOUND (err u104))
(define-constant ERR-FOREST-ALREADY-EXISTS (err u105))
(define-constant ERR-PARENT-MILESTONE-NOT-FOUND (err u106))
(define-constant ERR-MILESTONE-ALREADY-COMPLETED (err u107))
(define-constant ERR-PREREQUISITES-NOT-COMPLETED (err u108))
(define-constant ERR-INVALID-PARAMETERS (err u109))
(define-constant ERR-INVALID-USER-ROLE (err u110))
(define-constant ERR-LEARNER-NOT-REGISTERED (err u111))
(define-constant ERR-DUPLICATE-RELATIONSHIP (err u112))

;; =============================
;; Data Maps & Variables
;; =============================
;; User roles: 1=Admin, 2=Mentor, 3=Guardian, 4=Learner
(define-map learners
  { learner-id: principal }
  {
    role: uint,
    name: (string-ascii 100),
    registered-at: uint,
  }
)

;; Stores relationships: guardian-learner or mentor-learner
(define-map learner-relationships
  {
    primary-user: principal,
    related-user: principal,
  }
  { relationship-type: (string-ascii 20) } ;; "guardian-learner" or "mentor-learner"
)

;; Learning domains represent collections of milestone trees
(define-map learning-domains
  { domain-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    created-by: principal,
    created-at: uint,
  }
)

;; Milestone definitions
(define-map milestone-nodes
  { milestone-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 50),
    difficulty-level: uint, ;; 1-5 representing complexity
    domain-id: uint,
    parent-milestone-id: (optional uint),
    created-by: principal,
    created-at: uint,
  }
)

;; Tracks milestone progression by learners
(define-map milestone-progressions
  {
    milestone-id: uint,
    learner-id: principal,
  }
  {
    progressed-at: uint,
    verified-by: principal,
    evidence-link: (optional (string-utf8 500)),
  }
)

;; Milestone prerequisites
(define-map milestone-dependencies
  {
    milestone-id: uint,
    prerequisite-id: uint,
  }
  { added-at: uint }
)

;; Counters
(define-data-var milestone-id-counter uint u1)
(define-data-var domain-id-counter uint u1)

;; =============================
;; Private Functions
;; =============================
;; Check if a user is authorized to manage a learner's milestones
(define-private (can-manage-learner
    (manager-id principal)
    (learner-id principal)
  )
  (or
    (is-eq manager-id CONTRACT-OWNER)
    (match (map-get? learner-relationships {
      primary-user: manager-id,
      related-user: learner-id,
    })
      relationship
      true
      false
    )
  )
)

;; Increment milestone ID counter and return new value
(define-private (get-next-milestone-id)
  (let ((next-id (var-get milestone-id-counter)))
    (var-set milestone-id-counter (+ next-id u1))
    next-id
  )
)

;; Increment domain ID counter and return new value
(define-private (get-next-domain-id)
  (let ((next-id (var-get domain-id-counter)))
    (var-set domain-id-counter (+ next-id u1))
    next-id
  )
)

;; =============================
;; Read-Only Functions
;; =============================
;; Get learner information
(define-read-only (get-learner (learner-id principal))
  (map-get? learners { learner-id: learner-id })
)

;; Get milestone information
(define-read-only (get-milestone (milestone-id uint))
  (map-get? milestone-nodes { milestone-id: milestone-id })
)

;; Get learning domain information
(define-read-only (get-learning-domain (domain-id uint))
  (map-get? learning-domains { domain-id: domain-id })
)

;; Check if a milestone is progressed by a learner
(define-read-only (is-milestone-progressed
    (milestone-id uint)
    (learner-id principal)
  )
  (is-some (map-get? milestone-progressions {
    milestone-id: milestone-id,
    learner-id: learner-id,
  }))
)

;; Get milestone progression details
(define-read-only (get-milestone-progression
    (milestone-id uint)
    (learner-id principal)
  )
  (map-get? milestone-progressions {
    milestone-id: milestone-id,
    learner-id: learner-id,
  })
)

;; Get relationship between two users
(define-read-only (get-learner-relationship
    (primary-user principal)
    (related-user principal)
  )
  (map-get? learner-relationships {
    primary-user: primary-user,
    related-user: related-user,
  })
)

;; =============================
;; Public Functions
;; =============================
;; Register a new learner
(define-public (register-learner
    (name (string-ascii 100))
    (role uint)
  )
  (let ((learner-id tx-sender))
    (asserts! (and (>= role u1) (<= role u4)) ERR-INVALID-USER-ROLE)
    (asserts! (is-none (map-get? learners { learner-id: learner-id }))
      ERR-MILESTONE-ALREADY-EXISTS
    )
    (map-set learners { learner-id: learner-id } {
      role: role,
      name: name,
      registered-at: block-height,
    })
    (ok true)
  )
)

;; Create a milestone node
(define-public (create-milestone-node
    (title (string-ascii 100))
    (description (string-ascii 500))
    (category (string-ascii 50))
    (difficulty-level uint)
    (domain-id uint)
    (parent-milestone-id (optional uint))
  )
  (let (
      (learner-id tx-sender)
      (milestone-id (get-next-milestone-id))
    )
    ;; Ensure learning domain exists
    (asserts! (is-some (map-get? learning-domains { domain-id: domain-id }))
      ERR-FOREST-NOT-FOUND
    )
    ;; Validate difficulty level (1-5)
    (asserts! (and (>= difficulty-level u1) (<= difficulty-level u5))
      ERR-INVALID-PARAMETERS
    )
    ;; If parent milestone is specified, ensure it exists
    (asserts!
      (match parent-milestone-id
        parent-id (is-some (map-get? milestone-nodes { milestone-id: parent-id }))
        true
      )
      ERR-PARENT-MILESTONE-NOT-FOUND
    )
    (map-set milestone-nodes { milestone-id: milestone-id } {
      title: title,
      description: description,
      category: category,
      difficulty-level: difficulty-level,
      domain-id: domain-id,
      parent-milestone-id: parent-milestone-id,
      created-by: learner-id,
      created-at: block-height,
    })
    (ok milestone-id)
  )
)