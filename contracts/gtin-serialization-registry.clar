;; GTIN Serialization Registry Smart Contract
;; Manages unique Global Trade Item Numbers (GTINs), serial numbers, and packaging hierarchies
;; for pharmaceutical products to ensure complete supply chain traceability

;; Error codes for contract operations
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-GTIN (err u103))
(define-constant ERR-INVALID-SERIAL (err u104))
(define-constant ERR-PACKAGING-CONFLICT (err u105))
(define-constant ERR-BATCH-MISMATCH (err u106))
(define-constant ERR-INSUFFICIENT-PERMISSIONS (err u107))

;; Contract owner for administrative functions
(define-constant CONTRACT-OWNER tx-sender)

;; Maximum values for validation
(define-constant MAX-GTIN-LENGTH u14)
(define-constant MAX-SERIAL-LENGTH u20)
(define-constant MAX-BATCH-LENGTH u10)

;; Product registration data structure
(define-map products
    { gtin: (string-ascii 14) }
    {
        product-name: (string-utf8 100),
        manufacturer: principal,
        ndc-number: (string-ascii 11),
        lot-number: (string-ascii 10),
        expiration-date: uint,
        registration-date: uint,
        is-active: bool,
        temperature-sensitive: bool,
        dosage-form: (string-ascii 50)
    }
)

;; Serial number tracking for individual product instances
(define-map serial-numbers
    { gtin: (string-ascii 14), serial: (string-ascii 20) }
    {
        manufacturer: principal,
        production-date: uint,
        batch-number: (string-ascii 10),
        packaging-level: (string-ascii 20),
        parent-serial: (optional (string-ascii 20)),
        is-shipped: bool,
        current-holder: (optional principal),
        status: (string-ascii 20)
    }
)

;; Packaging hierarchy relationships (case -> pallet mappings)
(define-map packaging-hierarchy
    { parent-serial: (string-ascii 20), child-serial: (string-ascii 20) }
    {
        gtin: (string-ascii 14),
        relationship-type: (string-ascii 20),
        created-date: uint,
        created-by: principal
    }
)

;; Batch information for manufacturing lots
(define-map batch-info
    { gtin: (string-ascii 14), batch-number: (string-ascii 10) }
    {
        manufacturer: principal,
        production-date: uint,
        expiration-date: uint,
        quantity-produced: uint,
        quantity-shipped: uint,
        quality-status: (string-ascii 20),
        manufacturing-site: (string-ascii 100)
    }
)

;; Authorized manufacturers and distributors
(define-map authorized-entities
    { entity: principal }
    {
        entity-type: (string-ascii 20),
        company-name: (string-utf8 100),
        license-number: (string-ascii 50),
        authorization-date: uint,
        is-active: bool
    }
)

;; Track total products and serials registered
(define-data-var total-products-registered uint u0)
(define-data-var total-serials-registered uint u0)

;; Private function to validate GTIN format (basic validation)
(define-private (is-valid-gtin (gtin (string-ascii 14)))
    (and 
        (>= (len gtin) u8)
        (<= (len gtin) u14)
    )
)

;; Private function to validate serial number format
(define-private (is-valid-serial (serial (string-ascii 20)))
    (and 
        (>= (len serial) u1)
        (<= (len serial) u20)
    )
)

;; Private function to check if caller is authorized
(define-private (is-authorized-entity (entity principal))
    (match (map-get? authorized-entities { entity: entity })
        auth-info (get is-active auth-info)
        false
    )
)

;; Private function to get current block height as timestamp
(define-private (get-current-timestamp)
    stacks-block-height
)

;; Register a new pharmaceutical product with GTIN
(define-public (register-product 
    (gtin (string-ascii 14))
    (product-name (string-utf8 100))
    (ndc-number (string-ascii 11))
    (lot-number (string-ascii 10))
    (expiration-date uint)
    (temperature-sensitive bool)
    (dosage-form (string-ascii 50))
)
    (begin
        ;; Validate inputs
        (asserts! (is-valid-gtin gtin) ERR-INVALID-GTIN)
        (asserts! (is-authorized-entity tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (map-get? products { gtin: gtin })) ERR-ALREADY-EXISTS)
        
        ;; Store product information
        (map-set products
            { gtin: gtin }
            {
                product-name: product-name,
                manufacturer: tx-sender,
                ndc-number: ndc-number,
                lot-number: lot-number,
                expiration-date: expiration-date,
                registration-date: (get-current-timestamp),
                is-active: true,
                temperature-sensitive: temperature-sensitive,
                dosage-form: dosage-form
            }
        )
        
        ;; Increment product counter
        (var-set total-products-registered (+ (var-get total-products-registered) u1))
        
        (ok gtin)
    )
)

;; Register a serial number for a product instance
(define-public (register-serial-number
    (gtin (string-ascii 14))
    (serial (string-ascii 20))
    (batch-number (string-ascii 10))
    (packaging-level (string-ascii 20))
    (parent-serial (optional (string-ascii 20)))
)
    (begin
        ;; Validate inputs
        (asserts! (is-valid-gtin gtin) ERR-INVALID-GTIN)
        (asserts! (is-valid-serial serial) ERR-INVALID-SERIAL)
        (asserts! (is-authorized-entity tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? products { gtin: gtin })) ERR-NOT-FOUND)
        (asserts! (is-none (map-get? serial-numbers { gtin: gtin, serial: serial })) ERR-ALREADY-EXISTS)
        
        ;; Store serial number information
        (map-set serial-numbers
            { gtin: gtin, serial: serial }
            {
                manufacturer: tx-sender,
                production-date: (get-current-timestamp),
                batch-number: batch-number,
                packaging-level: packaging-level,
                parent-serial: parent-serial,
                is-shipped: false,
                current-holder: (some tx-sender),
                status: "PRODUCED"
            }
        )
        
        ;; Increment serial counter
        (var-set total-serials-registered (+ (var-get total-serials-registered) u1))
        
        (ok serial)
    )
)

;; Create packaging hierarchy relationship
(define-public (create-packaging-relationship
    (parent-serial (string-ascii 20))
    (child-serial (string-ascii 20))
    (gtin (string-ascii 14))
    (relationship-type (string-ascii 20))
)
    (begin
        ;; Validate authorization and inputs
        (asserts! (is-authorized-entity tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-gtin gtin) ERR-INVALID-GTIN)
        (asserts! (is-some (map-get? serial-numbers { gtin: gtin, serial: parent-serial })) ERR-NOT-FOUND)
        (asserts! (is-some (map-get? serial-numbers { gtin: gtin, serial: child-serial })) ERR-NOT-FOUND)
        
        ;; Store packaging relationship
        (map-set packaging-hierarchy
            { parent-serial: parent-serial, child-serial: child-serial }
            {
                gtin: gtin,
                relationship-type: relationship-type,
                created-date: (get-current-timestamp),
                created-by: tx-sender
            }
        )
        
        (ok true)
    )
)

;; Register batch information
(define-public (register-batch
    (gtin (string-ascii 14))
    (batch-number (string-ascii 10))
    (expiration-date uint)
    (quantity-produced uint)
    (manufacturing-site (string-ascii 100))
)
    (begin
        ;; Validate inputs and authorization
        (asserts! (is-valid-gtin gtin) ERR-INVALID-GTIN)
        (asserts! (is-authorized-entity tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? products { gtin: gtin })) ERR-NOT-FOUND)
        (asserts! (is-none (map-get? batch-info { gtin: gtin, batch-number: batch-number })) ERR-ALREADY-EXISTS)
        
        ;; Store batch information
        (map-set batch-info
            { gtin: gtin, batch-number: batch-number }
            {
                manufacturer: tx-sender,
                production-date: (get-current-timestamp),
                expiration-date: expiration-date,
                quantity-produced: quantity-produced,
                quantity-shipped: u0,
                quality-status: "RELEASED",
                manufacturing-site: manufacturing-site
            }
        )
        
        (ok true)
    )
)

;; Authorize a new entity (manufacturer/distributor)
(define-public (authorize-entity
    (entity principal)
    (entity-type (string-ascii 20))
    (company-name (string-utf8 100))
    (license-number (string-ascii 50))
)
    (begin
        ;; Only contract owner can authorize entities
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-INSUFFICIENT-PERMISSIONS)
        (asserts! (is-none (map-get? authorized-entities { entity: entity })) ERR-ALREADY-EXISTS)
        
        ;; Store authorization
        (map-set authorized-entities
            { entity: entity }
            {
                entity-type: entity-type,
                company-name: company-name,
                license-number: license-number,
                authorization-date: (get-current-timestamp),
                is-active: true
            }
        )
        
        (ok true)
    )
)

;; Transfer serial number ownership
(define-public (transfer-serial-ownership
    (gtin (string-ascii 14))
    (serial (string-ascii 20))
    (new-holder principal)
)
    (begin
        (asserts! (is-authorized-entity tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-authorized-entity new-holder) ERR-NOT-AUTHORIZED)
        
        (match (map-get? serial-numbers { gtin: gtin, serial: serial })
            serial-info
                (begin
                    (asserts! (is-eq (get current-holder serial-info) (some tx-sender)) ERR-NOT-AUTHORIZED)
                    (map-set serial-numbers
                        { gtin: gtin, serial: serial }
                        (merge serial-info { current-holder: (some new-holder), status: "TRANSFERRED" })
                    )
                    (ok true)
                )
            ERR-NOT-FOUND
        )
    )
)

;; Read-only functions for data retrieval

;; Get product information by GTIN
(define-read-only (get-product (gtin (string-ascii 14)))
    (map-get? products { gtin: gtin })
)

;; Get serial number information
(define-read-only (get-serial-info (gtin (string-ascii 14)) (serial (string-ascii 20)))
    (map-get? serial-numbers { gtin: gtin, serial: serial })
)

;; Get batch information
(define-read-only (get-batch-info (gtin (string-ascii 14)) (batch-number (string-ascii 10)))
    (map-get? batch-info { gtin: gtin, batch-number: batch-number })
)

;; Get packaging relationship
(define-read-only (get-packaging-relationship (parent-serial (string-ascii 20)) (child-serial (string-ascii 20)))
    (map-get? packaging-hierarchy { parent-serial: parent-serial, child-serial: child-serial })
)

;; Get authorization status
(define-read-only (get-authorization-status (entity principal))
    (map-get? authorized-entities { entity: entity })
)

;; Get registration statistics
(define-read-only (get-registration-stats)
    {
        total-products: (var-get total-products-registered),
        total-serials: (var-get total-serials-registered)
    }
)

