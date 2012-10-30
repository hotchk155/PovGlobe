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
volatile byte spinComplete;

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

// GLOBE
byte gl_top[65] = {0,	0,	48,	56,	56,	120,	112,	112,	240,	248,	252,	252,	248,	244,	240,	228,	252,	252,	254,	4,	14,	14,	63,	63,	31,	15,	6,	22,	0,	64,	224,	128,	224,	248,	252,	222,	238,	254,	254,	252,	248,	249,	248,	252,	252,	250,	252,	252,	248,	248,	248,	248,	240,	244,	244,	248,	248,	112,	112,	240,	48,	48,	32,	0};
byte gl_mid[65] = {0,	16,	0,	0,	0,	0,	0,	0,	3,	7,	15,	31,	31,	55,	51,	227,	235,	231,	225,	192,	192,	192,	128,	128,	128,	0,	0,	0,	48,	123,	127,	127,	253,	252,	252,	253,	252,	253,	253,	239,	95,	63,	59,	31,	7,	63,	127,	159,	15,	127,	255,	191,	239,	79,	103,	137,	134,	0,	1,	0,	0,	0,	0,	0};
byte gl_bot[65] = {0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	1,	3,	99,	127,	63,	31,	95,	15,	7,	7,	0,	0,	0,	0,	0,	0,	0,	3,	15,	31,	31,	31,	15,	7,	8,	4,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	1,	24,	29,	59,	62,	60,	24,	0,	0,	64,	32,	0};

//DEATH STAR
byte ds_top[65] = {255,	64,	198,	64,	88,	0,	101,	0,	255,	0,	84,	84,	0,	171,	128,	128,	248,	128,	213,	128,	0,	7,	252,	4,	228,	4,	60,	0,	255,	0,	128,	152,	136,	200,	15,	0,	240,	248,	12,	108,	108,	12,	248,	240,	0,	0,	0,	255,	4,	4,	20,	16,	223,	64,	74,	64,	66,	16,	18,	144,	18,	240,	18,	16};
byte ds_mid[65] = {23,	20,	151,	244,	148,	20,	244,	20,	23,	20,	22,	20,	244,	20,	20,	244,	21,	148,	20,	23,	212,	52,	23,	20,	21,	212,	52,	212,	63,	28,	20,	20,	20,	20,	20,	20,	20,	21,	247,	23,	23,	247,	21,	20,	244,	20,	20,	245,	20,	20,	20,	20,	23,	244,	20,	244,	22,	20,	20,	21,	244,	20,	20,	20};
byte ds_bot[65] = {0,	0,	115,	0,	31,	0,	1,	0,	255,	1,	9,	8,	15,	0,	0,	246,	16,	31,	0,	0,	7,	4,	12,	240,	4,	7,	16,	31,	240,	20,	21,	21,	21,	7,	32,	0,	80,	0,	7,	32,	0,	255,	0,	0,	33,	33,	32,	47,	40,	32,	63,	32,	40,	47,	0,	7,	0,	252,	0,	1,	7,	0,	248,	72};

byte *top = gl_top;
byte *mid = gl_mid;
byte *bot = gl_bot;

volatile int switcher;
volatile byte spinrate;
volatile char spindir;
byte stripes[3];

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

  // configure immediate switch to globe
  top = 0;
  switcher = 1;

  stripes[0] = 0;
  stripes[1] = 0;
  stripes[2] = 0;
 
  // enable global interrupts
  sei();
}


void delay_spins(int count)
{
  while(count-- > 0)
  {
    spinComplete = 0;
    while(!spinComplete);
  }
}

void loop(void)
{
  int i;
  stripes[0] = 0;
  stripes[1] = 0;
  stripes[2] = 0;
  delay_spins(200);
  
  unsigned long s1 = 0x800000;
  unsigned long s2 = 0x000001;
  for(i=0; i<23; ++i)
  {
    stripes[0] = (s1|s2);
    stripes[1] = (s1|s2) >> 8;
    stripes[2] = (s1|s2) >> 16;
    s1>>=1;
    s2<<=1;
    delay_spins(1);
  }
  switcher = 1;
  s1 = 0x800000;
  s2 = 0x000001;
  for(i=0; i<23; ++i)
  {
    stripes[0] = (s1|s2);
    stripes[1] = (s1|s2) >> 8;
    stripes[2] = (s1|s2) >> 16;
    s1>>=1;
    s2<<=1;
    delay_spins(1);
  }
  stripes[0] = 0;
  stripes[1] = 0;
  stripes[2] = 0;
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

  if(switcher)
  {
    if(top == gl_top)
    {
      top = ds_top;
      mid = ds_mid;
      bot = ds_bot;
      spindir = -1;
      spinrate = 1;
    }
    else
    {
      top = gl_top;
      mid = gl_mid;
      bot = gl_bot;
      spindir = 1;
      spinrate = 2;
    }
    switcher = 0;
  }
  
  spinComplete = 1;
  spins++;
  sector = 0;
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
    writeLEDs(stripes[0],stripes[1],stripes[2]);
  }
  else
  {
    int z;
    if(spindir>0) 
      z = 64-((sector/2 + spins/spinrate)%64);
    else
      z = (64 + spins/spinrate - sector/2)%64;    
    if(top)
      writeLEDs(top[z]|stripes[0],mid[z]|stripes[1],bot[z]|stripes[2]);
    else
      writeLEDs(stripes[0],stripes[1],stripes[2]);
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



