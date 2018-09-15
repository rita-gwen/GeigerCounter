;------------------------------------------------
;  	Project: Geiger counter11
;	Date: 2018-01-10
; 	Functionality
;		- count Geiger tube pulses. Calculate 60 seconds moving count of pulses with 5 seconds resolution
;		- monitor and regulate the Geiger tube HV to 400V +/- 4V 
;		- monitor the battery charging status. Shut/slow down the charging current when the battery reaches maximum voltage
;		- display pulse count, HV and battery status on display


;----------- Constant definitions
HV_ADC_IN_PIN 	con P9		; pin 18
PWM_OUT_PIN		con P3		; pin 9, B3

CHRG_POT_INC_PIN	con	P0		; B0  battery charget current control
CHRG_POT_UPDOWN_PIN	con P10		; pin 1, A2
CHRG_USBPWR_IND		con P11		; pin 2, A3 active when USB power connection is made. It also connects to 
							; FT232 RESET pin, be careful not to drive it low.
V_REF_PIN		con P7		; pin 13, B7 voltage reference from the power step up converter
V_BATTERY_PIN	con P8		; pin 17, A0 battery voltage measurement


PIN_DIR_IN	con 1
PIN_DIR_OUT	con	0

TIMER_POST_SCALER con 154		;TODO: Should be 144, 150 is a bit higher: 5.2 sec
BUFFER_SIZE		con 12

INITIALIZATION_STATE		con 0
COUNT_STATE					con	1
BATTERY_LOW_STATE			con 2

BATTERY_BIT_MASK		con 0x01	; 0 means 0; 1 means normal
USB_BIT_MASK			con 0x02	; 0 - disconnected, 1 - connected

;--------- Variable definitions
pwm_duration var word
pwm_duty var word
pwm_duty_new var word

high_voltage_adc	var	word
voltage_ref_adc		var word
voltage_battery_adc	var word
charge_current		var sbyte		; 32 bit value indicating current source wiper position that defines the charging current
charge_current_new	var sbyte		; input parameter to the setChrgCurr procedure

state_id	var byte
charge_state_id	var byte
shutdown_countdown	var byte
;-------- Counter ISR variables
tube_count	var word				;total count of all pulses since start up
tube_count_old var word	

timer_count	var byte				;timer post-scaler loop variable
count_buffer var word(BUFFER_SIZE)	;counts ring buffer
count_buffer_pointer	 var byte	;current ring buffer position
old_count_buffer_pointer var byte	;previous ring buffer position
total_time_count		var word	;count of total timer interrupts since power up.

i	var	byte
tmp	var byte

;------  LCD interface variables
lcd_data	var byte	; data byte to send to lcd
lcd_nib		var	byte	; what nib in lcd_data to send. 0 low nib, 1 high nib
lcd_rs		var byte	; content of the RS bit (0 low, 1 high)
lcd_line	var byte(17); a zero-terminated string to send to the dislpay
lcd_posx	var byte	; position of the cursor on the display. x is from 0 to 15
lcd_posy	var byte	; y is 0 or 1. The lcdSendString will put the charactes at his position

;------------- Variable initialization

state_id = INITIALIZATION_STATE
charge_state_id = 1
tmp = 0

main_loop:
	branch state_id, [do_initialization, do_normalCounting]			;, do_batteryLow]

do_initialization:			;----------------------------------------
	tube_count = 0
	tube_count_old = 0
	total_time_count = 0
	
	;ring buffer initialization
	count_buffer_pointer = 0
	old_count_buffer_pointer = 0
	for i = 0 to BUFFER_SIZE-1
		count_buffer(i) = 0
	next

	;-------------- Hardware configuration
	; Init the display and show welcome message
	gosub lcdInitGeiger
	lcd_line = rep " "\16
	lcd_line = "Powering up...", 0
	lcd_posx = 0
	lcd_posy = 0
	gosub lcdSendString
	lcd_line = hex tmp, 0
	lcd_posx = 0
	lcd_posy = 1
	gosub lcdSendString
	
	setPullUps PU_Off
	
	; initialize ADC pin and battery charger
	INPUT HV_ADC_IN_PIN
	INPUT V_REF_PIN
	INPUT V_BATTERY_PIN 
	INPUT CHRG_USBPWR_IND
	
	;  Start HV PWM
	pwm_duration = 2048 * 4		;1kHz base frequency
	pwm_duty = 920
	hpwm PWM_OUT_PIN, pwm_duration, pwm_duty 
	
	;  setup tube counter
	setTmr1	TMR1ASYNC1
	TMR1L = 0
	TMR1H = 0
	TMR1ON = 1
	
	;	Set up Timer 0 and enable interrupt.
	;   Timer 0 is used to signal 5 s intervals for the ring buffer shift 
	timer_count = TIMER_POST_SCALER		; for 5 s. TODO: Calibrate this time more precisely
	setTmr0 TMR0INT256
	TMR0IE = 1
	PEIE = 1                                     ; Enable the peripheral interrupts
	GIE = 1                                      ; Global interrupt enable
	
	if IN11 = 1 then					; if USB is connected initialize the battery charger
		; set the charge pot to 0 current (max resistance)
		HIGH CHRG_POT_INC_PIN			; -- High-to-low transitions
		HIGH CHRG_POT_UPDOWN_PIN		; -- High to increment, low to decrement
		for i = 1 to 32
			LOW CHRG_POT_INC_PIN
			HIGH CHRG_POT_INC_PIN
		next
		charge_current = 0	
	endif
	
	state_id = COUNT_STATE		;proceed to the counting state when initialization is complete
	goto	main_loop

;----------------
do_normalCounting:				;-------- Regular counting operation

	; Regulate HV
	; Monitor Battery
	; Update Display

	if count_buffer_pointer <> old_count_buffer_pointer then		;-- New counter reading is available
		adin HV_ADC_IN_PIN, high_voltage_adc
;		adin V_REF_PIN, voltage_ref_adc
		adin V_BATTERY_PIN, voltage_battery_adc

		; Correction for the 16 bit counter rolling over 0xFF
		if tube_count < tube_count_old then
			tube_count = tube_count - tube_count_old
			tube_count_old = 0
		endif 
		if IN11 = 1 then		;if USB port is connected
			serout s_out, i19200, ["{"]
			serout s_out, i19200, [0x22, "hv_adc", 0x22, 0x3A, dec high_voltage_adc]
			serout s_out, i19200, [0x2C, 0x22, "charge_current", 0x22, 0x3A, dec charge_current]
			serout s_out, i19200, [0x2C, 0x22, "bat_adc", 0x22, 0x3A, dec voltage_battery_adc]
			serout s_out, i19200, [0x2C, 0x22, "cpm", 0x22, 0x3A, dec (tube_count - tube_count_old)]
			serout s_out, i19200, [0x2C, 0x22, "count_buffer", 0x22, 0x3A, 0x22]
			for i = 0 to BUFFER_SIZE-1
				serout s_out, i19200, [" ", dec count_buffer(i)]
			next
			serout s_out, i19200, [0x22, 0x2C, 0x22, "buffer_pointer", 0x22, 0x3A, dec count_buffer_pointer]
			serout s_out, i19200, [0x2C, 0x22, "time_count", 0x22, 0x3A, dec total_time_count]
			serout s_out, i19200, ["}",  10]
			
;			serout s_out, i14400, [" USB IND:", bin IN11, ", Pulse count: ", 9]
;			serout s_out, i14400, [" Buffer increment ", dec (tube_count - tube_count_old), " Total Count: ", dec tube_count, " Old Count: " , dec tube_count_old, " tmp: ", hex tmp, 13]

			; update the battery charging current
			charge_current_new = (((950 - voltage_battery_adc)>>2)+6) max 32
			gosub setChargeCurr
		endif
		;Printing the display data
		lcd_line = rep " "\16
		lcd_line = "T:", dec tube_count 
		lcd_line(10) = 0
		lcd_posx = 0
		lcd_posy = 0
		gosub lcdSendString
		
		lcd_line = "CPM:", dec (tube_count - tube_count_old)		;"HV:", dec high_voltage_adc, 0
		lcd_posx =  9
		lcd_posy = 0
		gosub lcdSendString

		 
		if IN11 = 1 then
			tmp = "C"
		else
			tmp = " "
		endif
		i = ((voltage_battery_adc-670)>>1) max 99
		lcd_line = dec2 (total_time_count/720)\2, ":", dec2 (total_time_count/12//60)\2, ":", dec2 (total_time_count//12*5)\2, rep" "\3, str tmp\1, "B", dec i, "%"
		lcd_line(16) = 0
		
		lcd_posx =  0
		lcd_posy = 1
		gosub lcdSendString
		old_count_buffer_pointer = count_buffer_pointer
	endif
	pause 1000
	goto main_loop
	
	
;------------------------------------------------------------------------
; -- Set the charging current
setChargeCurr:

	if charge_current = charge_current_new then
		return
	endif
	
	if charge_current_new > charge_current then
		LOW CHRG_POT_UPDOWN_PIN
	else 
		HIGH CHRG_POT_UPDOWN_PIN
	endif
	for i = 1 to abs(charge_current_new - charge_current)
		LOW CHRG_POT_INC_PIN
		HIGH CHRG_POT_INC_PIN
	next
	charge_current = charge_current_new
;	drain_state.lownib = v_chrg_curr >> 1
return
	


;------------------------------------------------------------------------
;  Timer0 ISR to get the pulse counts into the ring buffer
;------------------------------------------------------------------------
israsm{                                 ; Interrupt dispatcher
	  btfsc	INTCON, TMR0IF				;go to timer interrupt if this is timer interrupt.
	  goto	timer0Int
	  btfsc	INTCON, INTF
	  goto	extInt						; Power button down interrupt
	  goto	endInterrupts
	  
timer0Int
	  banksel	timer_count&0x1FF		;decrement the post-scaler
	  decf		timer_count&0x7F, F
	  btfss		STATUS, Z				;if post-scaler register is 0
	  goto		timer0IntExit
	  
	  movlw		TIMER_POST_SCALER		;re-load the post-scaler
	  banksel	timer_count&0x1FF
	  movwf		timer_count&0x7F
	  
	  ;---------------- Tube count read -------------
	  ; 1. Set up indirect access to the current buffer location
	  ; 2. Save the content of the current buffer location into a temp variable A
	  ; 3. Read the timer and put it into the same location
	  ; 4. Subtract the temp variable A from the new timer read to get the running total (this can be done in basic)
	  ; 5. Increment the buffer location
	  ;
	  ;set up indirect access to move the count value into the next element of the ring buffer
	  bcf		STATUS, IRP				;set IRP bit
	  movlw		(count_buffer&0x1ff)>>8
	  btfss		STATUS, Z
	  bsf		STATUS, IRP
	  
	  banksel	count_buffer_pointer&0x1ff		;get current index value
	  bcf		STATUS, C
	  rlf		count_buffer_pointer&0x7f, w	; multiply by 2 (words)
	  addlw		count_buffer&0xFF				;add buffer address
	  movwf		FSR								;load the address into FSR

	  movf		INDF, w							;get the old value LB from the current buffer location
	  banksel	tube_count_old&0x1ff			;move it to the temp variable
	  movwf		tube_count_old&0x7f	;
	  incf 		FSR, f
	  movf		INDF, w							;get the old value HB from the current buffer location
	  movwf		(tube_count_old+1)&0x7f	;
	  decf		FSR , f 

readTimer:	  									;see example in the PIC16F8X datasheet page 74
	  banksel	TMR1H							;read the timer high byte and put it into the total count 
	  movf		TMR1H, w
	  incf		FSR, f
	  movwf		INDF							; put it into the buffer HB			
	  decf		FSR, f
	  
	  banksel	(tube_count	+ 1)&0x1ff
	  movwf		(tube_count	+ 1)&0x7f
	  
	  banksel	TMR1L							;read the timer low byte and put it into the total count 
	  movf		TMR1L, w

	  banksel	(tube_count)&0x1ff
	  movwf		(tube_count)&0x7f

	  movwf		INDF

	  banksel	TMR1H							;read the timer high byte again to verify the read 
	  movf		TMR1H, w
	  incf		FSR, f
	  subwf		INDF, w							;if total count still the same
	  btfsc		STATUS, Z
	  goto		goodRead						;the read is normal, proceed
badRead
	  movf		TMR1H, w						;the timer's LB rolled over, re-read
	  movwf		INDF

	  banksel	(tube_count	+ 1)&0x1ff
	  movwf		(tube_count	+ 1)&0x7f
	  
	  decf		FSR, f
	  banksel	TMR1L							;read the timer low byte and put it into the total count 
	  movf		TMR1L, w
	  movwf		INDF
	  
	  banksel	(tube_count)&0x1ff
	  movwf		(tube_count)&0x7f
	  
goodRead
	  banksel	total_time_count&0x1ff			;increment total time counter
	  incf		total_time_count&0x7f, f
	  btfsc		STATUS, Z
	  incf		(total_time_count + 1)&0x7f, f


	  ;ring buffer management
	  banksel	count_buffer_pointer&0x1ff		;get current index value
	  incf		count_buffer_pointer&0x7f, f	;increment the pointer in place
	  movf		count_buffer_pointer&0x7f, w	
	  sublw		BUFFER_SIZE						;compare with the buffer size
	  btfss		STATUS, Z	
	  goto		timer0IntExit	  				;if end of buffer reached
	  clrf		count_buffer_pointer&0x7f		;reset the index
	  
timer0IntExit	  
	  
	  nop
	  nop
	  nop
	  nop
;	  banksel	PORTA
;	  bcf		PORTA, 0
	  banksel	0
	  bcf	INTCON, TMR0IF
	  goto		endInterrupts
;----------------------------------------
extInt:
      
      nop
      nop
      bcf		INTCON, INTF
      
endInterrupts      
	  nop
}     


;------------------------------------------------------------------------------------	
;------------------------ Display interface code ------------------------------------
;
;
; Pin definitions in the hardware
LCD_E_PIN		con	P13		; A7
LCD_RS_PIN		con	P12		; A6
LCD_RW_PIN		con P11		; A3, TODO: to be implemented in the hardware
LCD_DAT4_PIN	con	P5		; B5
LCD_DAT5_PIN	con	P4		; B4
LCD_DAT6_PIN	con	P1		; B1
LCD_DAT7_PIN	con	P2		; B2

LCD_E_BIT		con	7		; A7
LCD_RS_BIT		con 6		; A6
LCD_RW_BIT		con 3		; A3
LCD_DAT4_BIT	con	5		; B5
LCD_DAT5_BIT	con	4		; B4
LCD_DAT6_BIT	con	1		; B1
LCD_DAT7_BIT	con	2		; B2

;----- Assembly function to send a nib to the display over the 4-bit bus
asm{
lcdSendNib:
	banksel	lcd_nib&0x1ff		;select the nib to send in the lcd_data byte
	movf	lcd_nib&0x7f, f
	btfsc 	STATUS, Z
	goto	loadByte			; jump if zero
	banksel	lcd_data&0x1ff		;swap the bytes
	swapf	lcd_data&0x7f, f
	goto 	rotateByte
loadByte:
	banksel	lcd_data&0x1ff		;use as is
	movf	lcd_data&0x7f, f
	
rotateByte:	

	;rotating right
	banksel	PortB					;clear the data bits
	bcf		PortB, LCD_DAT4_BIT
	bcf		PortB, LCD_DAT5_BIT
	bcf		PortB, LCD_DAT6_BIT
	bcf		PortB, LCD_DAT7_BIT
rot1
	banksel	lcd_data&0x1ff		
	rrf		lcd_data&0x7f, f
	btfss	STATUS, C
	goto	rot2
	banksel	PortB
	bsf		PortB, LCD_DAT4_BIT
rot2	
	banksel	lcd_data&0x1ff		
	rrf		lcd_data&0x7f, f
	btfss	STATUS, C
	goto	rot3
	banksel	PortB
	bsf		PortB, LCD_DAT5_BIT
rot3	
	banksel	lcd_data&0x1ff		
	rrf		lcd_data&0x7f, f
	btfss	STATUS, C
	goto	rot4
	banksel	PortB
	bsf		PortB, LCD_DAT6_BIT
rot4	
	banksel	lcd_data&0x1ff		
	rrf		lcd_data&0x7f, f
	btfss	STATUS, C
	goto	setRsLine
	banksel	PortB
	bsf		PortB, LCD_DAT7_BIT
setRsLine:
	banksel	lcd_rs&0x1ff
	movf	lcd_rs&0x7f, f
	btfsc	STATUS, Z
	goto	rsLow
	banksel	PortA
	bsf		PortA, LCD_RS_BIT
	goto	sendData
rsLow:	
	banksel	PortA
	bcf		PortA, LCD_RS_BIT
	
sendData						;toggle RS line to transmit the data
	bsf		PortA, LCD_E_BIT
	nop	
	nop	
	nop	
	nop	
	nop	
	nop	
	nop	
	nop	
	bcf		PortA, LCD_E_BIT
	
	banksel	0
	return
}

lcd_save_data	var byte

;---- send a byte in lds_data variable to the display
lcdSendByte				
	lcd_save_data = lcd_data
	lcd_nib = 1
	asm{ call lcdSendNib}
	lcd_data = lcd_save_data
	lcd_nib = 0
	asm{ call lcdSendNib}
	return	

;----- Send a byte as a command (RS line is low)	
lcdSendCommand
	lcd_rs = 0
	gosub lcdSendByte
	return	
	
;----- Send a byte as data (RS line is high)	
lcdSendData
	lcd_rs = 1
	gosub lcdSendByte
	return	

;------------------------------	
LCD_CLEAR_CMD		con 0x01
LCD_DDRAM_ADDR_CMD	con	0x80
LCD_CGRAM_ADDR_CMD	con	0x40

;------- Display initialization 	
lcdInitGeiger						;---

	; set Display pins to output low.
	low LCD_RS_PIN
;	low LCD_RW_PIN
	low LCD_DAT4_PIN
	low LCD_DAT5_PIN
	low LCD_DAT6_PIN
	low LCD_DAT7_PIN
	low LCD_E_PIN
	
	lcd_rs = 0

	lcd_data = 0x30			;-- power up sequence according to documentation (see SPLC780D.DS.pdf, page 11)
	lcd_nib = 1
	asm{ call lcdSendNib}
	pause	10	
	
	lcd_data = 0x30
	lcd_nib = 1
	asm{ call lcdSendNib}
	pause	1
	
	lcd_data = 0x30
	lcd_nib = 1
	asm{ call lcdSendNib}
	
	lcd_data = 0x20			;-- establish 4 bit comm mode
	lcd_nib = 1
	asm{ call lcdSendNib}
	pause	1

	lcd_data = 0x28			;-- 4 bit bus, 2 lines display
	gosub lcdSendCommand

							;-- Display initialization
	lcd_data = 0x0C			;display on, cursor on
	gosub lcdSendCommand
	
	lcd_data = 0x01			; clear display
	gosub lcdSendCommand
	pause 5
	
	lcd_data = 0x06			; entry mode: increment, no shift
	gosub lcdSendCommand

	lcd_data = 0x02			; move the cursor to 0,0 location
	gosub lcdSendCommand

	return
	
	
;----------- 
; Send a zero-terminated string in lcd_line array to the display.
; The string is placeds at lcd_posx, lcd_posy coordinates.
lcdSendString
	lcd_data = LCD_DDRAM_ADDR_CMD | (lcd_posy * 0x40 + lcd_posx)
	gosub lcdSendCommand
 	i = 0
	while lcd_line(i) <> 0 and i < 17
		lcd_data = lcd_line(i)
		gosub lcdSendData
		i = i+1
	wend	
	return