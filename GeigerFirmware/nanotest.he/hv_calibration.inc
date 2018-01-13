
;--------------------------------------------------------
;  Procedure used to calibrate HV measurement curcuit

hv_calibration
	;Get new duty cycle
	serout s_out, i9600, ["Enter new duty cycle (100-400)> "]
	serin s_in, i9600, [dec pwm_duty_new]
	serout s_out, i9600, [13, 10, "Setting new duty cycle to ", dec pwm_duty_new, 13]
	;
	;Set new cycle
	hpwm PWM_OUT_PIN, pwm_duration, pwm_duty_new
	pwm_duty = pwm_duty_new
	pause 2000
	for i = 1 to 4
		adin HV_ADC_IN_PIN, high_voltage_adc
		serout s_out, i9600, ["Duty cycle:", dec pwm_duty, "  Voltage raw: ", dec high_voltage_adc, 13]
		pause 1000
	next
	return
	
