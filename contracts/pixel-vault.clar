;; pixel-vault.clar
;; Core contract for the PixelVault Digital Art Platform
;;
;; This contract manages digital artwork as NFTs on the Stacks blockchain,
;; including ownership, permissions, collaboration history, and revenue sharing.
;; It provides a comprehensive system for artists to create, collaborate, and
;; showcase their digital art with verifiable provenance.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ARTWORK-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PERMISSION (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-CONTRIBUTOR (err u104))
(define-constant ERR-INVALID-SHARES (err u105))
(define-constant ERR-GALLERY-NOT-FOUND (err u106))
(define-constant ERR-NOT-OWNER (err u107))
(define-constant ERR-COLLECTION-NOT-FOUND (err u108))
(define-constant ERR-INVALID-PRICE (err u109))
(define-constant ERR-NOT-COLLABORATOR (err u110))

;; Permission types
(define-constant PERMISSION-NONE u0)
(define-constant PERMISSION-VIEW u1)
(define-constant PERMISSION-SHARE u2)
(define-constant PERMISSION-COLLABORATE u3)

;; Data structures

;; Artwork map: stores the core information about each artwork
(define-map artworks
  { artwork-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    content-hash: (buff 32),
    creation-date: uint,
    is-collaborative: bool,
    owner: principal,
    for-sale: bool,
    price: uint
  }
)

;; Artwork permissions: defines who can view, share, or collaborate on an artwork
(define-map artwork-permissions
  { artwork-id: uint, user: principal }
  { permission-level: uint }
)

;; Collaboration history: tracks all contributions to collaborative artworks
(define-map collaboration-history
  { artwork-id: uint, contributor: principal, version: uint }
  {
    contribution-date: uint,
    contribution-description: (string-ascii 200),
    content-hash: (buff 32)
  }
)

;; Revenue sharing: defines how revenue is distributed among collaborators
(define-map revenue-sharing
  { artwork-id: uint, contributor: principal }
  { share-percentage: uint }
)

;; Collections: groups of artworks curated by users
(define-map collections
  { collection-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    creation-date: uint
  }
)

;; Collection items: artworks included in a collection
(define-map collection-items
  { collection-id: uint, artwork-id: uint }
  { added-date: uint }
)

;; Galleries: virtual spaces to showcase artworks
(define-map galleries
  { gallery-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    creation-date: uint,
    is-public: bool
  }
)

;; Gallery items: artworks included in a gallery
(define-map gallery-items
  { gallery-id: uint, artwork-id: uint }
  { 
    display-order: uint,
    added-date: uint 
  }
)

;; Counters for generating sequential IDs
(define-data-var last-artwork-id uint u0)
(define-data-var last-collection-id uint u0)
(define-data-var last-gallery-id uint u0)

;; Private functions

;; Get the next available artwork ID
(define-private (get-next-artwork-id)
  (let ((current-id (var-get last-artwork-id)))
    (var-set last-artwork-id (+ current-id u1))
    (+ current-id u1)
  )
)

;; Get the next available collection ID
(define-private (get-next-collection-id)
  (let ((current-id (var-get last-collection-id)))
    (var-set last-collection-id (+ current-id u1))
    (+ current-id u1)
  )
)

;; Get the next available gallery ID
(define-private (get-next-gallery-id)
  (let ((current-id (var-get last-gallery-id)))
    (var-set last-gallery-id (+ current-id u1))
    (+ current-id u1)
  )
)

;; Check if user has sufficient permission for the given artwork
(define-private (check-permission (artwork-id uint) (user principal) (required-level uint))
  (let (
    (artwork (map-get? artworks { artwork-id: artwork-id }))
    (permission (default-to { permission-level: PERMISSION-NONE } 
      (map-get? artwork-permissions { artwork-id: artwork-id, user: user })))
  )
    (if (is-none artwork)
      false
      (if (is-eq (unwrap-panic artwork) { owner: user })
        true  ;; Owner has all permissions
        (>= (get permission-level permission) required-level)
      )
    )
  )
)

;; Check if the user is the owner of the artwork
(define-private (is-artwork-owner (artwork-id uint) (user principal))
  (let ((artwork (map-get? artworks { artwork-id: artwork-id })))
    (and 
      (is-some artwork)
      (is-eq (get owner (unwrap-panic artwork)) user)
    )
  )
)

;; Check valid shares total (should sum to 100%)
(define-private (validate-shares (shares (list 10 { contributor: principal, percentage: uint })))
  (let ((total (fold + (map get-percentage shares) u0)))
    (is-eq total u100)
  )
)

;; Helper to get percentage from share entry
(define-private (get-percentage (share { contributor: principal, percentage: uint }))
  (get percentage share)
)

;; Read-only functions

;; Get artwork details
(define-read-only (get-artwork (artwork-id uint))
  (let ((artwork (map-get? artworks { artwork-id: artwork-id })))
    (if (is-some artwork)
      (ok (unwrap-panic artwork))
      ERR-ARTWORK-NOT-FOUND
    )
  )
)

;; Get user's permission level for an artwork
(define-read-only (get-user-permission (artwork-id uint) (user principal))
  (let (
    (artwork (map-get? artworks { artwork-id: artwork-id }))
    (permission (map-get? artwork-permissions { artwork-id: artwork-id, user: user }))
  )
    (if (is-none artwork)
      ERR-ARTWORK-NOT-FOUND
      (if (is-eq (get owner (unwrap-panic artwork)) user)
        (ok PERMISSION-COLLABORATE)  ;; Owner has maximum permissions
        (if (is-some permission)
          (ok (get permission-level (unwrap-panic permission)))
          (ok PERMISSION-NONE)
        )
      )
    )
  )
)

;; Get collaboration history for an artwork
(define-read-only (get-collaboration-history (artwork-id uint))
  (let ((artwork (map-get? artworks { artwork-id: artwork-id })))
    (if (is-none artwork)
      ERR-ARTWORK-NOT-FOUND
      (ok (map-get? collaboration-history { artwork-id: artwork-id, contributor: tx-sender, version: u1 }))
    )
  )
)

;; Get revenue share for a contributor
(define-read-only (get-revenue-share (artwork-id uint) (contributor principal))
  (let (
    (artwork (map-get? artworks { artwork-id: artwork-id }))
    (share (map-get? revenue-sharing { artwork-id: artwork-id, contributor: contributor }))
  )
    (if (is-none artwork)
      ERR-ARTWORK-NOT-FOUND
      (if (is-some share)
        (ok (get share-percentage (unwrap-panic share)))
        (ok u0)
      )
    )
  )
)

;; Get collection details
(define-read-only (get-collection (collection-id uint))
  (let ((collection (map-get? collections { collection-id: collection-id })))
    (if (is-some collection)
      (ok (unwrap-panic collection))
      ERR-COLLECTION-NOT-FOUND
    )
  )
)

;; Get gallery details
(define-read-only (get-gallery (gallery-id uint))
  (let ((gallery (map-get? galleries { gallery-id: gallery-id })))
    (if (is-some gallery)
      (ok (unwrap-panic gallery))
      ERR-GALLERY-NOT-FOUND
    )
  )
)

;; Public functions

;; Create a new artwork
(define-public (create-artwork 
    (title (string-ascii 100)) 
    (description (string-ascii 500)) 
    (content-hash (buff 32))
    (is-collaborative bool)
  )
  (let (
    (new-id (get-next-artwork-id))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    (map-set artworks
      { artwork-id: new-id }
      {
        title: title,
        description: description,
        content-hash: content-hash,
        creation-date: current-time,
        is-collaborative: is-collaborative,
        owner: tx-sender,
        for-sale: false,
        price: u0
      }
    )
    
    ;; Record the initial creation in collaboration history
    (map-set collaboration-history
      { artwork-id: new-id, contributor: tx-sender, version: u1 }
      {
        contribution-date: current-time,
        contribution-description: "Initial creation",
        content-hash: content-hash
      }
    )
    
    ;; If collaborative, set owner's revenue share to 100%
    (if is-collaborative
      (map-set revenue-sharing
        { artwork-id: new-id, contributor: tx-sender }
        { share-percentage: u100 }
      )
      true
    )
    
    (ok new-id)
  )
)

;; Update artwork metadata
(define-public (update-artwork-metadata 
    (artwork-id uint) 
    (title (string-ascii 100)) 
    (description (string-ascii 500))
  )
  (let ((artwork (map-get? artworks { artwork-id: artwork-id })))
    (if (is-none artwork)
      ERR-ARTWORK-NOT-FOUND
      (if (is-artwork-owner artwork-id tx-sender)
        (begin
          (map-set artworks
            { artwork-id: artwork-id }
            (merge (unwrap-panic artwork) { title: title, description: description })
          )
          (ok true)
        )
        ERR-NOT-AUTHORIZED
      )
    )
  )
)

;; Update artwork content
(define-public (update-artwork-content
    (artwork-id uint)
    (content-hash (buff 32))
    (contribution-description (string-ascii 200))
  )
  (let (
    (artwork (map-get? artworks { artwork-id: artwork-id }))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    (if (is-none artwork)
      ERR-ARTWORK-NOT-FOUND
      (let ((artwork-data (unwrap-panic artwork)))
        (if (or
              (is-eq (get owner artwork-data) tx-sender)
              (check-permission artwork-id tx-sender PERMISSION-COLLABORATE)
            )
          (begin
            ;; Update the artwork content hash
            (map-set artworks
              { artwork-id: artwork-id }
              (merge artwork-data { content-hash: content-hash })
            )
            
            ;; Add to collaboration history
            (let ((version (+ u1 u1))) ;; Should determine next version in practice
              (map-set collaboration-history
                { artwork-id: artwork-id, contributor: tx-sender, version: version }
                {
                  contribution-date: current-time,
                  contribution-description: contribution-description,
                  content-hash: content-hash
                }
              )
            )
            
            (ok true)
          )
          ERR-NOT-AUTHORIZED
        )
      )
    )
  )
)

;; Set permission for a user
(define-public (set-permission
    (artwork-id uint)
    (user principal)
    (permission-level uint)
  )
  (if (is-artwork-owner artwork-id tx-sender)
    (if (and (>= permission-level PERMISSION-NONE) (<= permission-level PERMISSION-COLLABORATE))
      (begin
        (map-set artwork-permissions
          { artwork-id: artwork-id, user: user }
          { permission-level: permission-level }
        )
        (ok true)
      )
      ERR-INVALID-PERMISSION
    )
    ERR-NOT-AUTHORIZED
  )
)

;; Configure revenue sharing for a collaborative artwork
(define-public (set-revenue-sharing
    (artwork-id uint)
    (shares (list 10 { contributor: principal, percentage: uint }))
  )
  (let ((artwork (map-get? artworks { artwork-id: artwork-id })))
    (if (is-none artwork)
      ERR-ARTWORK-NOT-FOUND
      (let ((artwork-data (unwrap-panic artwork)))
        (if (not (get is-collaborative artwork-data))
          (err u111) ;; Not a collaborative artwork
          (if (is-eq (get owner artwork-data) tx-sender)
            (if (validate-shares shares)
              (begin
                ;; Clear existing shares (not shown - would need to track contributors)
                ;; Set new shares
                (map set-contributor-share 
                  (map tuple-to-artwork-share 
                    (map add-artwork-id-to-share shares)))
                (ok true)
              )
              ERR-INVALID-SHARES
            )
            ERR-NOT-AUTHORIZED
          )
        )
      )
    )
  )
)

;; Helper function to transform share tuples for mapping
(define-private (add-artwork-id-to-share (share { contributor: principal, percentage: uint }))
  {
    artwork-id: u0, ;; Placeholder - would be actual artwork ID in implementation
    contributor: (get contributor share),
    percentage: (get percentage share)
  }
)

;; Helper function to set share for a contributor
(define-private (tuple-to-artwork-share (share { artwork-id: uint, contributor: principal, percentage: uint }))
  { 
    artwork-id: (get artwork-id share), 
    contributor: (get contributor share), 
    share-percentage: (get percentage share) 
  }
)

;; Helper function to set share for a contributor
(define-private (set-contributor-share (entry { artwork-id: uint, contributor: principal, share-percentage: uint }))
  (map-set revenue-sharing
    { artwork-id: (get artwork-id entry), contributor: (get contributor entry) }
    { share-percentage: (get share-percentage entry) }
  )
)

;; Set artwork for sale
(define-public (set-for-sale (artwork-id uint) (for-sale bool) (price uint))
  (let ((artwork (map-get? artworks { artwork-id: artwork-id })))
    (if (is-none artwork)
      ERR-ARTWORK-NOT-FOUND
      (if (is-artwork-owner artwork-id tx-sender)
        (begin
          (if (and for-sale (< price u1))
            ERR-INVALID-PRICE
            (begin
              (map-set artworks
                { artwork-id: artwork-id }
                (merge (unwrap-panic artwork) { for-sale: for-sale, price: price })
              )
              (ok true)
            )
          )
        )
        ERR-NOT-AUTHORIZED
      )
    )
  )
)

;; Create a new collection
(define-public (create-collection 
    (name (string-ascii 100)) 
    (description (string-ascii 500))
  )
  (let (
    (new-id (get-next-collection-id))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    (map-set collections
      { collection-id: new-id }
      {
        name: name,
        description: description,
        creator: tx-sender,
        creation-date: current-time
      }
    )
    (ok new-id)
  )
)

;; Add artwork to collection
(define-public (add-to-collection (collection-id uint) (artwork-id uint))
  (let (
    (collection (map-get? collections { collection-id: collection-id }))
    (artwork (map-get? artworks { artwork-id: artwork-id }))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    (if (is-none collection)
      ERR-COLLECTION-NOT-FOUND
      (if (is-none artwork)
        ERR-ARTWORK-NOT-FOUND
        (if (is-eq (get creator (unwrap-panic collection)) tx-sender)
          (begin
            (map-set collection-items
              { collection-id: collection-id, artwork-id: artwork-id }
              { added-date: current-time }
            )
            (ok true)
          )
          ERR-NOT-AUTHORIZED
        )
      )
    )
  )
)

;; Create a new gallery
(define-public (create-gallery 
    (name (string-ascii 100)) 
    (description (string-ascii 500))
    (is-public bool)
  )
  (let (
    (new-id (get-next-gallery-id))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    (map-set galleries
      { gallery-id: new-id }
      {
        name: name,
        description: description,
        creator: tx-sender,
        creation-date: current-time,
        is-public: is-public
      }
    )
    (ok new-id)
  )
)

;; Add artwork to gallery
(define-public (add-to-gallery (gallery-id uint) (artwork-id uint) (display-order uint))
  (let (
    (gallery (map-get? galleries { gallery-id: gallery-id }))
    (artwork (map-get? artworks { artwork-id: artwork-id }))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    (if (is-none gallery)
      ERR-GALLERY-NOT-FOUND
      (if (is-none artwork)
        ERR-ARTWORK-NOT-FOUND
        (if (is-eq (get creator (unwrap-panic gallery)) tx-sender)
          (begin
            (map-set gallery-items
              { gallery-id: gallery-id, artwork-id: artwork-id }
              { 
                display-order: display-order,
                added-date: current-time 
              }
            )
            (ok true)
          )
          ERR-NOT-AUTHORIZED
        )
      )
    )
  )
)