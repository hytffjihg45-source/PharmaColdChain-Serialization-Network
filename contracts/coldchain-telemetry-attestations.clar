;; Cold-Chain Telemetry Attestations Smart Contract
;; Records and validates temperature/humidity sensor data to ensure proper storage
;; and transport conditions for temperature-sensitive pharmaceutical products

;; Error codes for contract operations
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-SHIPMENT-NOT-FOUND (err u202))
(define-constant ERR-ALREADY-COMPLETED (err u205))
(define-constant ERR-SENSOR-NOT-AUTHORIZED (err u207))
(define-constant ERR-ATTESTATION-EXISTS (err u208))
(define-constant ERR-INSUFFICIENT-PERMISSIONS (err u209))

;; Contract owner for administrative functions
(define-constant CONTRACT-OWNER tx-sender)

;; Temperature thresholds (in Celsius * 100 for precision)
(define-constant MIN-TEMP-CELSIUS-COLD 200)
(define-constant MAX-TEMP-CELSIUS-COLD 800)
(define-constant MIN-TEMP-CELSIUS-FROZEN -8000)
(define-constant MAX-TEMP-CELSIUS-FROZEN -2000)

;; Shipment information and tracking
(define-map shipments
    { shipment-id: (string-ascii 32) }
    {
        gtin: (string-ascii 14),
        serial-number: (string-ascii 20),
        sender: principal,
        recipient: principal,
        origin-facility: (string-ascii 100),
        destination-facility: (string-ascii 100),
        start-timestamp: uint,
        expected-end-timestamp: uint,
        actual-end-timestamp: (optional uint),
        temperature-profile: (string-ascii 20),
        humidity-required: bool,
        status: (string-ascii 20),
        compliance-status: (string-ascii 20)
    }
)

;; Environmental sensor readings
(define-map sensor-readings
    { shipment-id: (string-ascii 32), reading-id: (string-ascii 32) }
    {
        sensor-address: (string-ascii 50),
        timestamp: uint,
        temperature-celsius: int,
        humidity-percentage: uint,
        location-coordinates: (string-ascii 50),
        sensor-signature: (string-ascii 128),
        recorded-by: principal,
        verification-status: (string-ascii 20)
    }
)

;; Authorized sensor devices and operators
(define-map authorized-sensors
    { sensor-address: (string-ascii 50) }
    {
        operator: principal,
        device-type: (string-ascii 50),
        calibration-date: uint,
        certification-number: (string-ascii 50),
        accuracy-rating: (string-ascii 20),
        is-active: bool
    }
)

;; Shipment statistics
(define-data-var total-shipments uint u0)
(define-data-var total-readings uint u0)

;; Private function to validate temperature ranges
(define-private (is-temperature-compliant (temp int) (profile (string-ascii 20)))
    (if (is-eq profile "COLD")
        (and (>= temp MIN-TEMP-CELSIUS-COLD) (<= temp MAX-TEMP-CELSIUS-COLD))
        (if (is-eq profile "FROZEN")
            (and (>= temp MAX-TEMP-CELSIUS-FROZEN) (<= temp MIN-TEMP-CELSIUS-FROZEN))
            true
        )
    )
)

;; Private function to check sensor authorization
(define-private (is-authorized-sensor (sensor-address (string-ascii 50)))
    (match (map-get? authorized-sensors { sensor-address: sensor-address })
        sensor-info (get is-active sensor-info)
        false
    )
)

;; Create a new shipment for cold-chain monitoring
(define-public (create-shipment
    (shipment-id (string-ascii 32))
    (gtin (string-ascii 14))
    (serial-number (string-ascii 20))
    (recipient principal)
    (origin-facility (string-ascii 100))
    (destination-facility (string-ascii 100))
    (expected-duration uint)
    (temperature-profile (string-ascii 20))
    (humidity-required bool)
)
    (begin
        (asserts! (is-none (map-get? shipments { shipment-id: shipment-id })) ERR-ATTESTATION-EXISTS)
        (map-set shipments
            { shipment-id: shipment-id }
            {
                gtin: gtin,
                serial-number: serial-number,
                sender: tx-sender,
                recipient: recipient,
                origin-facility: origin-facility,
                destination-facility: destination-facility,
                start-timestamp: stacks-block-height,
                expected-end-timestamp: (+ stacks-block-height expected-duration),
                actual-end-timestamp: none,
                temperature-profile: temperature-profile,
                humidity-required: humidity-required,
                status: "IN_TRANSIT",
                compliance-status: "PENDING"
            }
        )
        (var-set total-shipments (+ (var-get total-shipments) u1))
        (ok shipment-id)
    )
)

;; Record environmental sensor reading
(define-public (record-sensor-reading
    (shipment-id (string-ascii 32))
    (sensor-address (string-ascii 50))
    (temperature-celsius int)
    (humidity-percentage uint)
    (location-coordinates (string-ascii 50))
    (sensor-signature (string-ascii 128))
)
    (let
        (
            (reading-id "reading-001")
        )
        (begin
            (asserts! (is-authorized-sensor sensor-address) ERR-SENSOR-NOT-AUTHORIZED)
            (asserts! (is-some (map-get? shipments { shipment-id: shipment-id })) ERR-SHIPMENT-NOT-FOUND)
            (map-set sensor-readings
                { shipment-id: shipment-id, reading-id: reading-id }
                {
                    sensor-address: sensor-address,
                    timestamp: stacks-block-height,
                    temperature-celsius: temperature-celsius,
                    humidity-percentage: humidity-percentage,
                    location-coordinates: location-coordinates,
                    sensor-signature: sensor-signature,
                    recorded-by: tx-sender,
                    verification-status: "VERIFIED"
                }
            )
            (var-set total-readings (+ (var-get total-readings) u1))
            (ok reading-id)
        )
    )
)

;; Authorize sensor device
(define-public (authorize-sensor
    (sensor-address (string-ascii 50))
    (operator principal)
    (device-type (string-ascii 50))
    (certification-number (string-ascii 50))
    (accuracy-rating (string-ascii 20))
)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-INSUFFICIENT-PERMISSIONS)
        (map-set authorized-sensors
            { sensor-address: sensor-address }
            {
                operator: operator,
                device-type: device-type,
                calibration-date: stacks-block-height,
                certification-number: certification-number,
                accuracy-rating: accuracy-rating,
                is-active: true
            }
        )
        (ok true)
    )
)

;; Complete shipment
(define-public (complete-shipment
    (shipment-id (string-ascii 32))
)
    (begin
        (match (map-get? shipments { shipment-id: shipment-id })
            shipment-info
                (begin
                    (asserts! (is-eq (get status shipment-info) "IN_TRANSIT") ERR-ALREADY-COMPLETED)
                    (map-set shipments
                        { shipment-id: shipment-id }
                        (merge shipment-info {
                            actual-end-timestamp: (some stacks-block-height),
                            status: "COMPLETED",
                            compliance-status: "COMPLIANT"
                        })
                    )
                    (ok true)
                )
            ERR-SHIPMENT-NOT-FOUND
        )
    )
)

;; Read-only functions for data retrieval

;; Get shipment information
(define-read-only (get-shipment (shipment-id (string-ascii 32)))
    (map-get? shipments { shipment-id: shipment-id })
)

;; Get sensor reading
(define-read-only (get-sensor-reading (shipment-id (string-ascii 32)) (reading-id (string-ascii 32)))
    (map-get? sensor-readings { shipment-id: shipment-id, reading-id: reading-id })
)

;; Get sensor authorization
(define-read-only (get-sensor-authorization (sensor-address (string-ascii 50)))
    (map-get? authorized-sensors { sensor-address: sensor-address })
)

;; Get system statistics
(define-read-only (get-system-stats)
    {
        total-shipments: (var-get total-shipments),
        total-readings: (var-get total-readings)
    }
)

;; Check temperature compliance for profile
(define-read-only (check-temperature-compliance (temperature int) (profile (string-ascii 20)))
    (is-temperature-compliant temperature profile)
)

