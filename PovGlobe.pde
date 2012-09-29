#include  <avr/io.h>
#include <avr/interrupt.h>
#include <Wire.h>

#define P_DATA0  8
#define P_DATA1  14
#define P_DATA2  15
#define P_SHCLK  10
#define P_STCLK  9
#define P_LED  7
#define P_HALL 2

#define IDEEPROM 0b1010000

#define NUM_SECTORS 64
volatile int sector;
volatile int spins = 0;

#define PORT_DATA0    PORTB
#define PORT_DATA1    PORTC
#define PORT_DATA2    PORTC
#define PORT_SHCLK   PORTB
#define PORT_STCLK   PORTB

#define BIT_DATA0    0x01
#define BIT_DATA1    0x01
#define BIT_DATA2    0x02
#define BIT_SHCLK   0x04
#define BIT_STCLK   0x02

#define SET_BIT(p,b) p |= b
#define CLR_BIT(p,b) p &= ~b

byte top[64] = {0,	0,	48,	56,	56,	120,	112,	112,	240,	248,	252,	252,	248,	244,	240,	228,	252,	252,	254,	4,	14,	14,	63,	63,	31,	15,	6,	22,	0,	64,	224,	128,	224,	248,	252,	222,	238,	254,	254,	252,	248,	249,	248,	252,	252,	250,	252,	252,	248,	248,	248,	248,	240,	244,	244,	248,	248,	112,	112,	240,	48,	48,	32,	0};
byte mid[64] = {0,	16,	0,	0,	0,	0,	0,	0,	3,	7,	15,	31,	31,	55,	51,	227,	235,	231,	225,	192,	192,	192,	128,	128,	128,	0,	0,	0,	48,	123,	127,	127,	253,	252,	252,	253,	252,	253,	253,	239,	95,	63,	59,	31,	7,	63,	127,	159,	15,	127,	255,	191,	239,	79,	103,	137,	134,	0,	1,	0,	0,	0,	0,	0};
byte bot[64] = {0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	1,	3,	99,	127,	63,	31,	95,	15,	7,	7,	0,	0,	0,	0,	0,	0,	0,	3,	15,	31,	31,	31,	15,	7,	8,	4,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	1,	24,	29,	59,	62,	60,	24,	0,	0,	64,	32,	0};

void writeLEDs(byte buf1, byte buf2, byte buf3)
{
  byte mask = 0x80;
  CLR_BIT(PORT_STCLK, BIT_STCLK);
  for(int i=0;i<8;++i)
  {
    CLR_BIT(PORT_SHCLK, BIT_SHCLK);    
    if(!!(mask & buf1)) SET_BIT(PORT_DATA0, BIT_DATA0); else CLR_BIT(PORT_DATA0, BIT_DATA0); 
    if(!!(mask & buf2)) SET_BIT(PORT_DATA1, BIT_DATA1); else CLR_BIT(PORT_DATA1, BIT_DATA1); 
    if(!!(mask & buf3)) SET_BIT(PORT_DATA2, BIT_DATA2); else CLR_BIT(PORT_DATA2, BIT_DATA2); 
    SET_BIT(PORT_SHCLK, BIT_SHCLK);
    mask>>=1;
  }
  SET_BIT(PORT_STCLK, BIT_STCLK);
}


//////////////////////////////////////////////////////////////////////////
//
// readEEPROM
//
//////////////////////////////////////////////////////////////////////////
void readEEPROM(unsigned int iAddress, byte *pbuf, int iLen)
{
  Wire.beginTransmission(IDEEPROM); //                               
  Wire.write((byte)(iAddress>>8)); // address MSB
  Wire.write((byte)iAddress);      // address LSB
  Wire.endTransmission();     
  Wire.requestFrom(IDEEPROM, iLen);
  
  while(iLen-- > 0)
  {
    *pbuf = Wire.read();
    pbuf++;
  } 
}

//////////////////////////////////////////////////////////////////////////
//
// writeEEPROM
//
//////////////////////////////////////////////////////////////////////////
void writeEEPROM(unsigned int iAddress, byte *pbuf, int iLen)
{
  Wire.beginTransmission(IDEEPROM); //                               
  Wire.write((byte)(iAddress>>8)); // address MSB
  Wire.write((byte)iAddress);      // address LSB
  while(iLen-- > 0)
  {
     Wire.write(*pbuf);
    pbuf++;
  }  
  Wire.endTransmission();     
}


void setup(void)
{
    pinMode(P_DATA0, OUTPUT);
    pinMode(P_DATA1, OUTPUT);
    pinMode(P_DATA2, OUTPUT);
    pinMode(P_SHCLK, OUTPUT);
    pinMode(P_STCLK, OUTPUT);

    pinMode(P_LED, OUTPUT);

    pinMode(P_HALL, INPUT);
    digitalWrite(P_HALL, HIGH);

  // setup serial
  Serial.begin(9600);

  // Setup I2C  
//  Wire.begin(); // join i2c bus (address optional for master)
  
  // disable interrupts
  cli();
  
  // setup timer0 - 8bit
  // resonsible for timing the LEDs
  TCCR2A = 0;
  TCCR2B = 0;  
  // select CTC mode
  TCCR2A |= (1<<WGM21);
//  bitset(TCCR2A,  WGM21);
  // select prescaler clk 
  
  // CS22 CS21 SCS20
  // 0    0    1      1
  // 0    1    0      8
  // 0    1    1      32
  // 1    0    0      64
  // 1    0    1      128
  // 1    1    0      256
  // 1    1    1      1024
  TCCR2B |= (1<<CS22);
  TCCR2B &= ~(1<<CS21);
  TCCR2B &= ~(1<<CS20);
  
  // enable compare interrupt
  TIMSK2 |= (1<<OCIE2A);

  // setup timer1 - 16bit
  // responsible for timing the rotation of the platter
  TCCR1B = 0;
  TCCR1A = 0;
  
  // select prescaler 
  // CS12 CS11 CS10
  // 0    0    1      1
  // 0    1    0      8
  // 0    1    1      64
  // 1    0    0      256
  // 1    0    1      1024 
  TCCR1B &= ~(1<<CS12);
  TCCR1B |= (1<<CS11);
  TCCR1B |= (1<<CS10);
  
  // reset timer
  TCNT1 = 0;
  // enable overflow interrupt
  TIMSK1 |= (1<<TOIE1);
  
  // configure the platter interrupt PIN
  // int0, on falling
  EICRA = _BV(ISC01);
  // Enable the hardware interrupt.
  EIMSK |= _BV(INT0);
 
  // enable global interrupts
  sei();
}

void loop(void)
{
}

//////////////////////////////////////////////////////////////////////////
//
// INT0_vect
// 
// Called when the opto interruptor is triggered (at the start of a new
// revolution
//
//////////////////////////////////////////////////////////////////////////
ISR(INT0_vect)
{
  // Store the rev time
  unsigned int uiRevTime = TCNT1;
  
  // Reset the timer which measures rev time
  TCNT1 = 0;
  
  // Reset the timer which controls LED switching
  TCNT2 = 0;

  sector = 0;
  spins++;
  OCR2A = uiRevTime / 128;
}

//////////////////////////////////////////////////////////////////////////
//
// TIMER2_COMPA_vect
// 
// Called when timer 2 reaches period register (this happens at the start
// of each segment)
//
//////////////////////////////////////////////////////////////////////////
ISR(TIMER2_COMPA_vect) 
{  
  if(!!(sector&1))
  {
    writeLEDs(0,0,0);
  }
  else
  {
    int z = 64-((sector/2 + spins/4)%64);
    writeLEDs(top[z],mid[z],bot[z]);
  }
  ++sector;
}

//////////////////////////////////////////////////////////////////////////
//
// TIMER1_0VF_vect
//
// Timer 1 overflow
// 
//////////////////////////////////////////////////////////////////////////
ISR(TIMER1_0VF_vect) 
{
}



