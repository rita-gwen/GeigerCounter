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
i	var	byte
;pulse_count_int	var byte
pulse_count_total	var word	;total tount of all pulses since start up
count_buffer_total	var word	; moving sum of the ring buffer

timer_count	var byte
count_buffer var byte(BUFFER_SIZE)
count_buffer_pointer	var byte


pwm_duration = 2048 * 4
pwm_duty = 950

timer_count = TIMER_POST_SCALER

;pulse_count_int = 0
count_buffer_pointer = 0

for i = 0 to BUFFER_SIZE
	count_buffer(i) = 0
next



hpwm PWM_OUT_PIN, pwm_duration, pwm_duty 

;	enable EXT interrupt
;INTEDG = 1                                ; Set the edge the interrupt will occur on, 1=Rising Edge and 0=Falling Edge   
;INTE = 1                                    ; Enable the Port 0 interrupt
PEIE = 1                                     ; Enable the peripheral interrupts
GIE = 1                                      ; Global interrupt enable

setTmr1	TMR1ASYNC1
TMR1L = 0
TMR1H = 0
TMR1ON	 = 1


;	Set up Timer 0 and enable interrupt.
;   Timer 0 is used to signal 5 s intervals for the ring buffer shift 
setTmr0 TMR0INT256
TMR0IE = 1

;DIR8 = PIN_DIR_OUT

mainLoop

	; Regulate HV
	; Monitor Battery
	; Update Display
;	pulse_count_int = TMR1L	;get the current count from the Timer1 register
	
	adin HV_ADC_IN_PIN, high_voltage_adc
	serout s_out, i14400, ["Duty cycle:", dec pwm_duty, "  Voltage raw: ", dec high_voltage_adc, ", Pulse count: ", dec count_buffer(0), " ", dec count_buffer(1), " ", dec count_buffer(2), " ", dec count_buffer(3), " ", dec count_buffer(4), " Timer Count: ", dec timer_count, 13]
	pause 2000
		
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
	  movlw		count_buffer>>8
	  btfss		STATUS, Z
	  bsf		STATUS, IRP
	  movlw		count_buffer&0xFF				;load buffer address
	  banksel	count_buffer_pointer&0x1ff		;add current index value
	  addwf		count_buffer_pointer&0x7f, w	
	  incf		count_buffer_pointer&0x7f, f		;increment the pointer
	  movwf		FSR								;load the address into FSR
	  
	  banksel	TMR1L					;move counter register content into the ring buffer
	  movf		TMR1L, w
	  movwf		INDF					;
	  clrf		TMR1L					;reset the counter
	  
	  banksel	count_buffer_pointer&0x1ff		;get current index value
	  movf		count_buffer_pointer&0x7f, w	
	  sublw		BUFFER_SIZE					;compare with the buffer size
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

	
	