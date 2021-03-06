;--- Brushed ESC V2 By Rolf R Bakke, May 2012. Braking with reverse power and adjustable dragbrake.

;--- modified by Sean D'Epagnier 2017 <seandepagnier@gmail.com>
        
;; LED states
;;; red=off           -  in bootloader
;;; red=flashing      - disarmed
;;; red=solid         - armed
;;; green=off         - motor not running
;;; green=on          - motor is running
        
.include "m8def.inc"
        ;;  add others when tested
#if defined(afro_nfet_esc)
#include "afro_nfet.inc"	; AfroESC 3 with all nFETs (ICP PWM, I2C, UART)
#endif

#if defined(bs_nfet_esc)
#include "bs_nfet.inc"	; AfroESC 3 with all nFETs (ICP PWM, I2C, UART)
#endif

#if defined(tp_nfet_esc)
#include "tp_nfet.inc"	; AfroESC 3 with all nFETs (ICP PWM, I2C, UART)
#endif
        
;#if !USE_ICP                    
;#error "currently only icp supported"
;#endif

        
;**** SETTINGS ****

.equ	BrakeStrength = 0	;0 to 127
.equ    MaxSlewRate = 16        ;1 to 127
.equ	DeadBand = 24		;n/127n parts
.equ	ThrottleNeutral = 1500	;uS

;******************
.def	t=r16
.def	Phase=r17
.def	PwmOut=r18
.def	Throttle=r19
.def	tisp=r20
.def	sregsave=r21
.def	resetflags=r22
.def	Counter=r23
.def    softwd=r24
.def    overtempcount=r25
.equ	BOOT_JUMP	= 1	; Jump to any boot loader when PW
.equ	BOOT_START	= THIRDBOOTSTART


.if inverted_high_side
.macro	sbix
	cbi @0, @1
.endmacro
.macro	cbix
	sbi @0, @1
.endmacro
.else
.macro	sbix
	sbi @0, @1
.endmacro
.macro	cbix
	cbi @0, @1
.endmacro
.endif        

.macro	a_top_on
	sbix ApFET_port, ApFET
.endmacro
.macro	a_top_off
	cbix ApFET_port, ApFET
.endmacro

.macro	b_top_on
	sbix BpFET_port, BpFET
.endmacro
.macro	b_top_off
	cbix BpFET_port ,BpFET
.endmacro

.macro	c_top_on
	sbix CpFET_port, CpFET
.endmacro
.macro	c_top_off
	cbix CpFET_port, CpFET
.endmacro

.macro	a_bottom_on
        sbi AnFET_port, AnFET
.endmacro
.macro	a_bottom_off
	cbi AnFET_port, AnFET
.endmacro
.macro	b_bottom_on
	sbi BnFET_port, BnFET
.endmacro
.macro	b_bottom_off
	cbi BnFET_port, BnFET
.endmacro
.macro	c_bottom_on
	sbi CnFET_port, CnFET
.endmacro
.macro	c_bottom_off
	cbi CnFET_port, CnFET
.endmacro



.if !defined(red_led)
	.macro RED_on
	.endmacro
	.macro RED_off
	.endmacro
.endif

.if !defined(green_led)
	.macro GRN_on
	.endmacro
	.macro GRN_off
	.endmacro
.endif

.macro outi
	ldi	t, @1
	out	@0, t
.endmacro
.macro	ldx
	ldi xl, low(@0)
	ldi xh, high(@0)
.endmacro
.macro	ldy
	ldi yl, low(@0)
	ldi yh, high(@0)
.endmacro
.macro	ldz
	ldi zl, low(@0)
	ldi zh, high(@0)
.endmacro
        
.org 0
	rjmp reset
	rjmp unused
	rjmp unused
	rjmp unused
	rjmp timer2overflow
	rjmp unused
	rjmp unused
	rjmp unused
	rjmp unused
	rjmp timer0overflow
	rjmp unused
	rjmp unused
	rjmp unused
	rjmp unused
	rjmp unused
	rjmp unused
	rjmp unused
	rjmp unused
	rjmp unused

unused:	reti

reset:	in resetflags, mcucsr
	outi mcucsr, 0
        ldi overtempcount, 25   ; start out overtemp
        rjmp reset3
reset2: clr resetflags
reset3:
        ldi Counter, 0
 	outi	WDTCR, (1<<WDCE)+(1<<WDE) 
 	out	WDTCR, Counter		; Disable watchdog

;        outi   GICR, (1<<IVCE)  
;        outi   GICR, 0
        
	outi spl, low(ramend)
	outi sph, high(ramend)

	;--- Port setup ---
        outi PORTB, INIT_PB
        outi PORTC, INIT_PC
        outi PORTD, INIT_PD

	outi DDRB, DIR_PB
	outi DDRC, DIR_PC
	outi DDRD, DIR_PD

        a_bottom_off
        b_bottom_off
        c_bottom_off
        a_top_off
        b_top_off
        c_top_off

        rcall strobe_swd

.if F_CPU == 8000000         ; timeout 200 milliseconds to receive signal
        outi OSCCAL, 190     
.endif        
        
#if 1
        ;;  --- bootloader test ---
        ;; half a second to enter bootloader if pwm pin is held high
        clr t
boot_loader_test1:
        inc t
        sbrc t, 6               ; 64 iterati
        rjmp boot_loader_jump
	ldz 62100
	rcall delay
	sbic	RCP_IN_port, rcp_in		; Skip clear if ICP pin h
        rjmp boot_loader_test1
#endif

        RED_off
        GRN_off
	;--- Timer 1 setup ---
	outi tccr1a, 0
	outi tccr1b, (1<<CS11)  ;2 MHz

	;--- ISR setup ---
	outi tccr0, (1<<CS00)   ; no prescale

        rcall strobe_swd 
        outi tccr2, (1<<CS20) | (1<<CS21) | (1<<CS22) ; overflows 61 times per second
	outi timsk, (1<<TOIE0) | (1<<TOIE2)  ; interrupt on overflow

	                        ;--- ADC setup ---
#if admux_temperature
 	outi admux, admux_temperature
 	outi adcsra, (1<<ADEN) | (1<<ADSC) | (1<<ADFR) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0)
#endif
	;--- Variables setup ---
	clr Throttle

	;--- Reset cause signalling ---
        sei
	rcall wms

re1:       
	sbrs resetflags, 2	;Brown out reset
	rjmp re2

	ldx 300
	ldy 900
	rcall sound
	ldi zl,0
	rcall wms
	ldx 300
	ldy 1000
	rcall sound
	ldi zl,0
	rcall wms
	ldx 300
	ldy 1100
	rcall sound
        ;rjmp boot_loader_jump
	rjmp re5

re2:       
	sbrs resetflags, 1	;external reset
	rjmp re3

	ldx 300
	ldy 1000
	rcall sound
	ldi zl,0
	rcall wms
	ldx 300
	ldy 900
	rcall sound
        
	rjmp re5

re3:        
	sbrs resetflags, 0	;power on reset
	rjmp re4
	ldx 500
	ldy 1000
	rcall sound
	rjmp re5
re4:    
	sbrs resetflags, 3	;watchdog reset
	rjmp re5
       
.if F_CPU != 8000000            ; timer2 broken on this?, dont do alarm
	ldx 100
	ldy 1200
	rcall sound
	ldx 200
	ldy 1000
	rcall sound
	ldx 100
	ldy 1400
	rcall sound
.endif
re5:        
	;--- arming ---
        RED_on
        GRN_off

        outi WDTCR, (1<<WDCE)+(1<<WDE)
        outi WDTCR, (1<<WDE)+(1<<WDP2)+(1<<WDP0) ;

        rjmp ar4                ; skip arming

ar2:	ldi Counter, 0
ar1:	rcall GetPwm
        
	ldy ThrottleNeutral - 20
	cp  xl, yl
	cpc xh, yh
	brlo ar2		;too low, reset counter

	ldy ThrottleNeutral + 20
	cp  xl, yl
	cpc xh, yh
	brsh ar2		;too high, reset counter

	ldy 500			;in range, make short sound
	ldx 5
	rcall sound

	inc Counter		;increase counter
	cpi Counter, 10		;10 in a row?
	brne ar1		;no, arming not OK

	;--- Armed sound ---

	ldi Counter, 20
	ldy 2000
ar3:	ldx 20
	rcall sound
	sbiw YH:YL, 63
	dec Counter
	brne ar3

	clr zl
	rcall wms
ar4:
	;--- Main loop ---
ma1:
	rcall GetPwm		;get input PWM value

	subi xl, low(ThrottleNeutral)	;subtract throttle neutral
	sbci xh, high(ThrottleNeutral)

	asr xh			;divide by 2
	ror xl
	asr xh			;divide by 2
	ror xl

;;;  if far out of range, reset
	ldy 200			;limit upper value
        cp xl, yl
        cpc xh, yh
        brlt in_range
	ldy -200			;limit lower value
        cp xl, yl
        cpc xh, yh
        brge in_range
        rjmp reset2
in_range:       
        ;b_bottom_on ;;  turn bottom b on, allowing channel to be used for clutch
        
	ldy 127			;limit upper value
	cp  xl, yl
	cpc xh, yh
	brlt ma2
	ldx 127                 
ma2:
	ldy -127		;limit lower value
	cp  xl, yl
	cpc xh, yh
	brge ma3
	ldx -127
ma3:
#if admux_temperature
	in yl, adcl		;High temp?
	in yh, adch
	
	ldz temperature_hot                 ;  overtemp at 60C
	cp yl, zl
	cpc yh, zh
        .if     temperature_pos > 0
        brlo ma4                
        .else
	brsh ma4
        .endif

        inc overtempcount
        cpi overtempcount, 25   ; overtemp for 500ms second or more??
	brlo ma4a
        dec overtempcount       ; to avoid overflow

	clr Throttle            ; turn off motor

	ldx 150			;yes, sound the alarm until it has cooled down
	ldy 1200
	rcall sound
	ldx 100
	ldy 2000
	rcall sound

	rcall wms
	rcall wms
        
	rjmp ma1
ma4:
        clr overtempcount
ma4a:    
#endif
        ; Set Throttle
        mov t, xl
        sub t, Throttle
        
        breq ma1               ; already set
        brlt ma5
        ; command greater than throttle
        cpi t, MaxSlewRate
        brlo ma6
        ldi t, MaxSlewRate         ; exceeded slew rate
        rjmp ma6
ma5:    ; command is less than throttle
        cpi t, -MaxSlewRate
        brsh ma6
        ldi t, -MaxSlewRate        ; exceeded slew rate
ma6:    ; update throttle
        GRN_on
        add Throttle, t
	rjmp ma1


	;--- SUBS ---
	
GetPwm: ;--- get PWM input value ---
        rcall strobe_swd
	;wait for low to high transition on ppm input
        
ge1:	sbic	RCP_IN_port, rcp_in		; Skip clear if ICP pin h
	rjmp ge1
        cbi RCP_IN_port, rcp_in
ge2:	sbis	RCP_IN_port, rcp_in		; Skip clear if ICP pin h
	rjmp ge2

	;start counting

	clr t
	out tcnt1h, t
	out tcnt1l, t

	;wait for low edge

ge3:    sbic	RCP_IN_port, rcp_in		; Skip clear if ICP pin h
	rjmp ge3

	;get time

	in xl, tcnt1l
	in xh, tcnt1h
.if F_CPU == 16000000           ; divide by 2
        asr xh                  
        ror xl
.endif

;;;  temperature compensation disabled, comment line below to enable
        ret                     ; skip temp comp

	in yl, adcl		;temperature compensation
	in yh, adch

	subi yl, low(823)
	sbci yh, high(823)

	asr yh
	ror yl
	asr yh
	ror yl
	asr yh
	ror yl

	sub xl, yl
	sbc xh, yh

	ret


	;--- ISR ---

timer0overflow:
	in sregsave, sreg
	ldi tisp, 0x80		;reload ISR counter
	out tcnt0, tisp

	inc Phase		;PWM generator
	cpi Phase, 128
	brne tm1


	;this part is run once, right at the start of the PWM period. 

	clr Phase

	mov PwmOut, Throttle	;sample throttle value

	cpi PwmOut, DeadBand	;brake or power?
	brge tm4
	cpi PwmOut, -DeadBand
	brlt tm4
        GRN_off

.if BrakeStrength > 0   
	a_bottom_on		;Brake.
	c_bottom_on
.endif	
	ldi PwmOut, BrakeStrength
	rjmp tm2

tm4:
        GRN_on
        tst PwmOut		;Power. Which direction?
	brmi tm3


	;forward

;debug_on

	a_top_on
	nop		;delay to let top FET turn on before the bottom FET (NFET are better at switching under load)
	nop
	nop
	c_bottom_on
	rjmp tm2


	;reverse

tm3:
;debug_on
	neg PwmOut

	c_top_on
	nop		;delay to let top FET turn on before the bottom FET
	nop
	nop
	a_bottom_on
	rjmp tm2


	; This part turns off the transistors when Phase is => PwmOut

tm1:	cp Phase, PwmOut
	brlo tm2

	a_bottom_off	;bottom off first to let the top switch without current
	c_bottom_off
	a_top_off
	c_top_off


	;exit
tm2:
;debug_off
	out sreg, sregsave
	reti

timer2overflow:
        subi softwd, 1
        breq reset_ov
        reti
reset_ov:
        rjmp reset2

	;--- Sound generation ---

sound:	cli

	a_bottom_off
	c_bottom_off
	a_top_off
	c_top_off

	ldz 100
	rcall delay

so1:
        
        rcall strobe_swd 
	a_top_on
	nop
	nop
	nop
	c_bottom_on

	ldz 200
	rcall delay
	
	a_bottom_off
	c_bottom_off
	a_top_off
	c_top_off

	movw ZH:ZL, YH:YL
	rcall delay

	c_top_on
	nop
	nop
	nop
	a_bottom_on

	ldz 200
	rcall delay
	
	a_bottom_off
	c_bottom_off
	a_top_off
	c_top_off

	movw ZH:ZL, YH:YL
	rcall delay

	sbiw XH:XL,1
	brne so1
	
	sei
	ret

        ;; implement software watchdog using timer2
strobe_swd:
        wdr
.if F_CPU == 8000000         ; timeout 200 milliseconds to receive signal
        ldi softwd, 10
.else
        ldi softwd, 20
.endif
        ret

	;--- Delay ---

delay:	sbiw ZH:ZL, 1
	brne delay
	ret

.if F_CPU == 8000000         ; timeout 200 milliseconds to receive signal
wms:	 ldi t,117	; wait zl ms
.else
wms:	 ldi t,235	; wait zl ms
.endif
wm1:	  ldi zh,11	;34
wm2:	  dec zh
	  brne wm2
	 dec t
	 brne wm1
	dec zl
	brne wms
	ret





;-----bko-----------------------------------------------------------------
boot_loader_jump:
	ldx 1000
	ldy 2500
	rcall sound
        
	cli
        
        ldi Counter, 0
        wdr
 	outi	WDTCR, (1<<WDCE)+(1<<WDE)
 	out	WDTCR, Counter		; Disable watchdog
.if F_CPU == 8000000         ; timeout 200 milliseconds to receive signal
        outi OSCCAL, 0xff       
.endif        
	a_bottom_off
	b_bottom_off
	c_bottom_off
	a_top_off
	b_top_off
	c_top_off
	rcall wms

        clr t
	out	DDRB, t		; Tristate pins
	out	DDRC, t
	out	DDRD, t

	rjmp	BOOT_START		; Jump to boot loader
