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

pulse_count_total	var word	;total tount of all pulses since start up
count_buffer_total	var word	; moving sum of the ring buffer

timer_count	var byte				;timer post-scaler loop variable
count_buffer var byte(BUFFER_SIZE)	;counts ring buffer
count_buffer_pointer	var byte	;current ring buffer position
old_count_buffer_pointer	var byte	

i	var	byte

;------------- Variable initialization
pwm_duration = 2048 * 4		;1kHz base frequency
pwm_duty = 950

timer_count = TIMER_POST_SCALER

;ring buffer initialization
count_buffer_pointer = 0
old_count_buffer_pointer = 0
for i = 0 to BUFFER_SIZE-1
	count_buffer(i) = 0
next
pulse_count_total = 0
count_buffer_total = 0


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
		serout s_out, i14400, ["Duty cycle:", dec pwm_duty, "  Voltage raw: ", dec high_voltage_adc, ", Pulse count: ", 9, dec count_buffer(0), " ", dec count_buffer(1), " ", dec count_buffer(2), " ", dec count_buffer(3), " ", dec count_buffer(4), 9, " Buffer total ", dec count_buffer_total, " Total Count: ", dec pulse_count_total, 13]
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
										;use indirect access to move the count value into the next element of the ring buffer
	  bcf		STATUS, IRP				;set IRP bit
	  movlw		(count_buffer&0x1ff)>>8
	  btfss		STATUS, Z
	  bsf		STATUS, IRP
	  movlw		count_buffer&0xFF				;load buffer address
	  
	  banksel	count_buffer_pointer&0x1ff		;add current index value
	  addwf		count_buffer_pointer&0x7f, w	
	  movwf		FSR								;load the address into FSR

	  movf		INDF, w							;get the old value from the current buffer location
	  banksel	count_buffer_total&0x1ff		;subtract it from the moving sum
	  subwf		count_buffer_total&0x7f, f	
	  btfss		STATUS, C
	  decf		(count_buffer_total + 1)&0x7f, f	
  

readTimer:	  
	  banksel	TMR1L							;read counter register content into W
	  movf		TMR1L, w						;TODO: implement 16 bit counter logic. Right now we are limited to 26 pulses per second.
	  movwf		INDF							;and put into the buffer's current location
	  clrf		TMR1L							;reset the counter
	  banksel	pulse_count_total&0x1ff			;add timer count to the total count. The reading is still in W
	  addwf		pulse_count_total&0x7f, f
	  btfsc		STATUS, C
	  incf 		(pulse_count_total + 1)&0x7f, f
	  
	  banksel	count_buffer_total&0x1ff		;calculate buffer moving sum
	  addwf		count_buffer_total&0x7f, f		;add current timer reading from W
	  btfsc		STATUS, C
	  incf		(count_buffer_total + 1)&0x7f, f	
	  
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

	
	