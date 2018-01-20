;------------------------------------------------
;  	Project: Geiger counter
;	Date: 2018-01-10
; 	Functionality
;		- count Geiger tube pulses. Calculate 60 seconds moving count of pulses with 5 seconds resolution
;		- monitor and regulate the Geiger tube HV to 400V +/- 4V 
;		- monitor the battery charging status. Shut/slow down the charging current when the battery reaches maximum voltage
;		- display pulse count, HV and battery status on display


pause 500

;----------- Constant definitions
HV_ADC_IN_PIN 	con P9
PWM_OUT_PIN		con P3
GEIGER_EXTI_PIN	con P0

PIN_DIR_IN	con 1
PIN_DIR_OUT	con	0

TIMER_POST_SCALER con 150
BUFFER_SIZE		con 5


;--------- Variable definitions
pwm_duration var word
pwm_duty var word
pwm_duty_new var word

high_voltage_adc	var	word

tube_count	var word	;total tount of all pulses since start up
tube_count_old var word	

timer_count	var byte				;timer post-scaler loop variable
count_buffer var word(BUFFER_SIZE)	;counts ring buffer
count_buffer_pointer	var byte	;current ring buffer position
old_count_buffer_pointer	var byte	;previous ring buffer position

i	var	byte

;------------- Variable initialization
pwm_duration = 2048 * 4		;1kHz base frequency
pwm_duty = 950

timer_count = TIMER_POST_SCALER

tube_count = 0
tube_count_old = 0

;ring buffer initialization
count_buffer_pointer = 0
old_count_buffer_pointer = 0
for i = 0 to BUFFER_SIZE-1
	count_buffer(i) = 0
next


;-------------- Hardware configuration
;  Start HV PWM
hpwm PWM_OUT_PIN, pwm_duration, pwm_duty 

;  setup tube counter
setTmr1	TMR1ASYNC1
TMR1L = 0
TMR1H = 0
TMR1ON	 = 1


;	Set up Timer 0 and enable interrupt.
;   Timer 0 is used to signal 5 s intervals for the ring buffer shift 
setTmr0 TMR0INT256
TMR0IE = 1
PEIE = 1                                     ; Enable the peripheral interrupts
GIE = 1                                      ; Global interrupt enable


;---------------- Main Loop

mainLoop

	; Regulate HV
	; Monitor Battery
	; Update Display
;	pulse_count_int = TMR1L	;get the current count from the Timer1 register
	if count_buffer_pointer <> old_count_buffer_pointer then
		adin HV_ADC_IN_PIN, high_voltage_adc
		serout s_out, i14400, ["Duty cycle:", dec pwm_duty, "  Voltage raw: ", dec high_voltage_adc, ", Pulse count: ", 9, dec count_buffer(0), " ", dec count_buffer(1), " ", dec count_buffer(2), " ", dec count_buffer(3), " ", dec count_buffer(4), 9]
		serout s_out, i14400, [" Buffer total ", dec (tube_count - tube_count_old), " Total Count: ", dec tube_count, " Old Count: " , dec tube_count_old, " Buffer index: ", dec count_buffer_pointer, 13]
		old_count_buffer_pointer = count_buffer_pointer
	endif
	pause 1000
		
goto mainLoop




israsm{                                 ; Interrupt dispatcher
	  btfsc	INTCON, TMR0IF				;go to timer interrupt if this is timer interrupt.
	  goto	timer0Int
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
	  ; 2. Save the current buffer location into a temp variable A
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
	  banksel	tube_count_old&0x1ff	;move it to the temp variable
	  movwf		tube_count_old&0x7f	;
	  incf 		FSR, f
	  movf		INDF, w							;get the old value HB from the current buffer location
	  movwf		(tube_count_old+1)&0x7f	;
	  decf		FSR , f 

readTimer:	  
	  banksel	TMR1H							;read the timer high byte and put it into the total count 
	  movf		TMR1H, w
	  incf		FSR, f
	  movwf		INDF								; put it into the buffer HB			
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
	  goto		goodRead					;the read is normal, proceed

	  movf		TMR1H, w
	  movwf		INDF
	  decf		FSR, f
	  banksel	TMR1L							;read the timer low byte and put it into the total count 
	  movf		TMR1L, w
	  movwf		INDF
	  
goodRead
	  
	  ;ring buffer management
	  banksel	count_buffer_pointer&0x1ff		;get current index value
	  incf		count_buffer_pointer&0x7f, f	;increment the pointer in place
	  movf		count_buffer_pointer&0x7f, w	
	  sublw		BUFFER_SIZE						;compare with the buffer size
	  btfss		STATUS, Z	
	  goto		timer0IntExit	  				;if end of buffer reached
	  clrf		count_buffer_pointer&0x7f		;reset the index
	  

timer0IntExit	  
	  
	  banksel	TRISA
	  BcF		TRISA, 0
	  banksel	PORTA
	  bsf		PORTA, 0
	  nop
	  nop
	  nop
	  nop
	  nop
	  nop
	  nop
	  nop
	  nop
	  banksel	PORTA
	  bcf		PORTA, 0
	  banksel	0
	  bcf	INTCON, TMR0IF
      
      
endInterrupts      
	  nop
}     

;#include "hv_calibration.inc"

	
	