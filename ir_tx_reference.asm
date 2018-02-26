;**********************************************************************
;   IR Remote Control Transmitter Reference Implementation            *
;                                                                     *
;**********************************************************************
;                                                                     *
;    Filename: txref.asm                                              *
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
		#include    "p16F628A.inc"	; processor specific variable definitions

		errorlevel  -302		; suppress message 302 from list file

		; __config 0x3F10
		__CONFIG    _FOSC_INTOSCIO & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _BOREN_OFF & _LVP_OFF & _CPD_OFF & _CP_OFF

;***** VARIABLE DEFINITIONS
; i/o ports
datain		equ PORTB			; data to be transmitted
ir_B		equ PORTA			; infrared output byte
ir_b		equ RA0				; ...bit
transmit_B	equ PORTA			; transmit byte (pull low to transmit)
transmit_b	equ RA5				; ...bit
transmitting_B	equ PORTA			; transmitting byte (low - transmitting, high - not transmitting)
transmitting_b	equ RA1				; ...bit

; file registers
txdata		equ 0x20			; byte to transmit
shiftc		equ 0x21			; shift counter
prd		equ 0x22
c1		equ 0x23			; counter
c2		equ 0x24			; counter

;**********************************************************************
		org 0x000			; processor reset vector

; initialise device
		; disbale comparators
		movlw   0x07
		movwf   CMCON
		
		bsf     STATUS,RP0		; switch to bank 1
		
		; ir output
		bcf     ir_B,ir_b
		
		; transmitting
		bcf	transmitting_B,transmitting_b
		
		; set up timer0
		bcf	OPTION_REG,T0CS
		bcf	OPTION_REG,PSA
		bcf	OPTION_REG,PS1
		bcf	OPTION_REG,PS2
		;bcf	OPTION_REG,NOT_RBPU
		
		bcf     STATUS,RP0		; switch to bank 0

		; initialise output pin states
		bcf     ir_B,ir_b
		bsf	transmitting_B,transmitting_b


; *********
; main loop
; ---------
main		; transmit?
		btfsc	transmit_B,transmit_b
		goto	main
		
		; indicate transmitting
		bcf	transmitting_B,transmitting_b
		
		; data to transmit
		movf	datain,w
		movwf	txdata

		; send header (3 marks/2 intervals of 932us)
		movlw	0xe3
                call    mark
		movlw	0xe3
                call    mark

		; send data
                ; initialise shift counter
                movlw   0x08
                movwf   shiftc
                ; send data
tx_loop1        movlw	0x89
                btfsc	txdata,0
                movlw	0xb5
                call	mark
		btfsc	txdata,0
		bsf	STATUS,C
                rrf     txdata,f
                decfsz  shiftc,f
                goto    tx_loop1
                ; send inverted data
                movlw   0x08
                movwf   shiftc
                comf    txdata,f
tx_loop2        movlw	0x89
                btfsc	txdata,0
                movlw	0xb5
                call	mark
                rrf     txdata,f
                decfsz  shiftc,f
                goto    tx_loop2
		
		; closing mark
		clrw
		call	mark
		
		; indicate not transmitting
		bsf	transmitting_B,transmitting_b

                ; signal gap
                movlw	0x5d
		movwf	c1
		movlw	0x18
		movwf	c2
sgloop		decfsz	c1, f
		goto	sgloop
		decfsz	c2, f
		goto	sgloop
		
		goto	main


; *****************************************
; transmit mark and wait w * 4us (approx.)
; -----------------------------------------
mark		movwf	prd
		clrf	TMR0
		movlw	0x0a
		movwf	c1
loop_sp		bsf     ir_B,ir_b
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		bcf	ir_B,ir_b
		;nop				; uncomment for ~38Khz
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		decfsz	c1,f
		goto	loop_sp
waitprd		movf	TMR0,w
		subwf	prd,w
		btfsc	STATUS,C
		goto	waitprd
		return
; -----------------------------------------
; *****************************************

; initialize eeprom locations
		org	0x2100
		de	0x00, 0x01, 0x02, 0x03


		end                         ; directive 'end of program'
