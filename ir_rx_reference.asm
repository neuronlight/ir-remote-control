;**********************************************************************
;   IR Remote Control Receiver Reference Implementation               *
;                                                                     *
;**********************************************************************
;                                                                     *
;    Filename: rxref.asm                                              *
;    Date: 21-FEB-2018                                                *
;    File Version: 1.0                                                *
;                                                                     *
;    Author: Simon Buckwell                                           *
;    Copyright: (c) Simon Buckwell                                    *
;    Licence: GNU GPLv3                                               *
;                                                                     *
;**********************************************************************
;                                                                     *
;    Files Required: P16F628A.INC                                     *
;                                                                     *
;**********************************************************************
;                                                                     *
;    Notes:                                                           *
;                                                                     *
;**********************************************************************

		list	    p=16f628A		; list directive to define processor
		#include    "p16f628a.inc"	; processor specific variable definitions

		errorlevel  -302		; suppress message 302 from list file

		; CONFIG
		; __config 0x3F10
		__CONFIG    _FOSC_INTOSCIO & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _BOREN_OFF & _LVP_OFF & _CPD_OFF & _CP_OFF




;***** VARIABLE DEFINITIONS
; port/pin assignments
ir_B		equ PORTB			; ir receiver module byte
ir_b		equ RB0				; ...bit
datardy_B	equ PORTA			; data-ready byte
datardy_b	equ RA1				; ...bit
dataack_B	equ PORTA			; data-acknowledge byte
dataack_b	equ RA5				; ...bit
siglost_B	equ PORTA			; signal lost byte
siglost_b	equ RA4				; ...bit
invout_B	equ PORTA			; invert output byte
invout_b	equ RA2				; ...bit

outbuf		equ 0x20			; output buffer

; variables
rxpack		equ 0x70			; rx decoded packet
rxdata		equ 0x71			; rx data
rxinvt		equ 0x72			; rx data (inverted)
rxldrc		equ 0x73			; rx leader mark counter
rxstat		equ 0x74			; rx data status (bit 7 - signal ok, bit 6 - data ready, bits 4-0 - bits received counter)
rxdatardy	equ 0x06			; bit 6 of rxstat (0 - data not ready, 1 - data ready)
rxsigok		equ 0x07			; bit 7 of rxstat (0 - signal lost, 1 - signal ok)
tmrbuf		equ 0x75			; tmr0 buffer
c1		equ 0x70			; counter for stabilisation delay (note - reuse of same reg at rxpack)
c2		equ 0x71			; counter for stabilisation delay (note - reuse of same reg at rxdata)

; system register buffers
wbuf		equ 0x7e			; w buffer
statbuf		equ 0x7f			; status buffer
;**********************************************************************
		org	0x000			; processor reset vector
		goto	init
		
		org	0x004			; interrupt vector
		goto	global_isr
		
		
; initialise device
init
		; turn off comparators
		movlw	0x07
		movwf	CMCON
		
		bsf	STATUS,RP0		; switch to bank 1
		
		; configure port/pins
		movlw	b'00000001'
		movwf	TRISB
		bcf	PORTA,0
		bcf	datardy_B,datardy_b
		bcf	siglost_B,siglost_b
		
		; set up timer0 (prescaler 1:4)
		bcf	OPTION_REG,T0CS
		bcf	OPTION_REG,PSA
		bcf	OPTION_REG,PS1
		bcf	OPTION_REG,PS2
		
		; configure interrupt on falling-edge on RB0/INT
		bcf	OPTION_REG,INTEDG
		
		; enable interrupt on timer1 overflow
		bsf	PIE1,TMR1IE
		
		bcf	STATUS,RP0		; switch to bank 0
		
		; initialise outputs
		clrf	PORTB
		bcf	PORTA,0
		bsf	datardy_B,datardy_b
		bsf	siglost_B,siglost_b
		
		; enable interrupt on RB0/INT
		bsf	INTCON,INTE
		
		; enable peripheral interrupts
		bsf	INTCON,PEIE
		
		; short delay to allow sensor to stabilise
		movlw	0x5d
		movwf	c1
		movlw	0x18
		movwf	c2
stblloop	decfsz	c1, f
		goto	stblloop
		decfsz	c2, f
		goto	stblloop
				
		; set timer1 prescaler to 1:8
		bsf	T1CON,T1CKPS0
		bsf	T1CON,T1CKPS1
		
		; clear variables
		clrf	rxstat
		clrf	rxpack
		clrf	rxldrc
		
		; start receiving
		call	rxstart
		
		; enable global interrupts
		bsf	INTCON,GIE
		
main		; signal lost?
		btfss	rxstat,rxsigok
		bcf	siglost_B,siglost_b
		btfsc	rxstat,rxsigok
		bsf	siglost_B,siglost_b
		
		; data ready?
		btfss	rxstat,rxdatardy
		bsf	datardy_B,datardy_b
		btfsc	rxstat,rxdatardy
		bcf	datardy_B,datardy_b
		
		; data acknowledged?
		btfss	rxstat,rxdatardy
		goto	outpack
		btfss	dataack_B,dataack_b	; data acknowledged?
		call	rxstart
		
outpack		; output received packet
		movf	rxpack,w
		btfss	invout_B,invout_b
		comf	rxpack,w
		call	display
		
		goto	main

; *************************************************
; display buffer to leds
; -------------------------------------------------
display		movwf	PORTB
		movwf	outbuf
		btfss	outbuf,0
		bcf	PORTA,0
		btfsc	outbuf,0
		bsf	PORTA,0
		return
; -------------------------------------------------
; *************************************************


; *************************************************
; start receiving
; -------------------------------------------------
rxstart		; clear data-ready bit
		bcf	rxstat,rxdatardy
		; set signal-ok bit
		bsf	rxstat,rxsigok
		; reset and (re)start timer1
		clrf	TMR1L
		clrf	TMR1H
		bsf	T1CON,TMR1ON
		; (re)enable interrupt on RB0/INT
		bsf	INTCON,INTE
		; return
		return
; -------------------------------------------------
; *************************************************


; *************************************************
; global interrupt service routine
; -------------------------------------------------
global_isr	; store w and status
		movwf	wbuf
		swapf	STATUS,w
		movwf	statbuf
		; redirect to external or timer1-overflow handler
		btfsc	INTCON,INTF
		goto	decode_isr		; signal decode interrupt service routine
		btfsc	PIR1,TMR1IF
		goto	timeout_isr		; timer1 overflow interrupt service routine
intrtn		; reinstate w and status, then return
		swapf	statbuf,w
		movwf	STATUS
		swapf	wbuf,f
		swapf	wbuf,w
		retfie
; -------------------------------------------------
; *************************************************


; *************************************************
; decode incomming signal interrupt service routine
; -------------------------------------------------
decode_isr	; store and reset tmr0
		movf	TMR0,w
		movwf	tmrbuf
		clrf	TMR0
		; if timer0 overflowed (i.e. space > 1020us) then clear leader and bit counters (mark treated as 1st leader)
		btfss	INTCON,T0IF
		goto	dec_1stldr
		bcf	INTCON,T0IF
		clrf	rxldrc
		movlw	b'11100000'
		andwf	rxstat,f
dec_1stldr	; 1st leader mark?
		btfsc	rxldrc,1
		goto	dec_space
		btfsc	rxldrc,0
		goto	dec_space
		movlw	0x01
		movwf	rxldrc
		; no space to measure - return
		goto	dec_rtn
dec_space	; space > 844us ? - leader
		movf	tmrbuf,w
		sublw	0xd3
		btfsc	STATUS,C
		goto	dec_bit
		; clear bit counter (bits 0-4)
		movlw	b'11100000'
		andwf	rxstat,f
		; leader mark counter at max already?
		btfss	rxldrc,0
		goto	dec_inc
		btfss	rxldrc,1
		goto	dec_inc
		; already received 3 leaders - ignore if bit counter zero, fail otherwise
		btfsc	rxstat,0
		goto	dec_fail
		btfsc	rxstat,1
		goto	dec_fail
		btfsc	rxstat,2
		goto	dec_fail
		btfsc	rxstat,3
		goto	dec_fail
		goto	dec_rtn
dec_inc		; inc leader mark counter
		incf	rxldrc,f
		goto	dec_rtn
dec_bit		; if leader bits not set then fail
		btfss	rxldrc,0
		goto	dec_fail
		btfss	rxldrc,1
		goto	dec_fail
dec_1		; space > 668us ? - '1'
		movf	tmrbuf,w
		sublw	0xa7
		btfsc	STATUS,C
		goto	dec_0
		bsf	STATUS,C
		goto	dec_store
dec_0		; space > 492us ? - '0'
		movf	tmrbuf,w
		sublw	0x7b
		btfsc	STATUS,C
		goto	dec_fail
		bcf	STATUS,C
dec_store	; store C in rxdata/rxinvt
		btfss	rxstat,3
		rrf	rxdata,f
		rrf	rxinvt,f		; yes, rxinvt gets filled with garbage during rxdata writing
		incf	rxstat,f
		; finshed?
		btfss	rxstat,4
		goto	dec_rtn
		; data validation (check rxdata is complement of rxinvt)
		movf	rxdata,w
		xorwf	rxinvt,f
		comf	rxinvt,w
		btfss	STATUS,Z
		goto	dec_fail
		; **** packet aquired! ****
		; stop timer1
		bcf	T1CON,TMR1ON
		; write to rxpack
		movf	rxdata,w
		movwf	rxpack
		; reset leader counter and rxstat
		clrf	rxldrc
		clrf	rxstat
		bsf	rxstat,rxdatardy
		bsf	rxstat,rxsigok
		; disable interrupt on RB0/INT
		bcf	INTCON,INTE
dec_rtn		; clear interrupt flag and return
		bcf	INTCON,INTF
		goto	intrtn
		
dec_fail	; decode failed - reset and return
		movlw	b'10000000'
		andwf	rxstat,f
		clrf	rxldrc
		goto	intrtn
; -------------------------------------------------
; *************************************************


; *************************************************
; timeout interrupt service routine
; -------------------------------------------------
timeout_isr	; clear signal-ok bit in rxstat
		bcf	rxstat,rxsigok
		; clear rxpack
		clrf	rxpack
		; stop timer1
		bcf	T1CON,TMR1ON
		; clear interrupt flag and return
		bcf	PIR1,TMR1IF
		goto	intrtn
; -------------------------------------------------
; *************************************************


; initialize eeprom locations
		org	0x2100
		de	0x00, 0x01, 0x02, 0x03

; directive 'end of program'
		end