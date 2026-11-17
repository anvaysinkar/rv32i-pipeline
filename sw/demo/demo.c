// demo.c - Nexys4 board demo for the RV32I pipeline
//
//   7-seg digits 7..4 : current switch value (hex)
//   7-seg digits 3..0 : a counter that ticks about 10 times a second
//   LEDs              : a light bouncing left and right
//   BTNC              : clear the counter
//   BTNU              : while held, the counter runs 4x faster
//   BTND              : while held, show measured CPI x 100 in decimal
//                       (e.g. 0115 means 1.15 cycles per instruction)
#include <stdint.h>

#define REG(a)    (*(volatile uint32_t *)(a))
#define LED       REG(0x20000000)
#define SWITCH    REG(0x20000004)
#define SEVENSEG  REG(0x20000008)
#define BUTTON    REG(0x2000000C)
#define CYCLES    REG(0x20000014)
#define INSTRET   REG(0x20000018)

#define BTN_C  (1u << 0)
#define BTN_U  (1u << 1)
#define BTN_D  (1u << 4)

#ifndef CORE_HZ
#define CORE_HZ 50000000u          // must match the MMCM output in nexys4_top.v
#endif

// RV32I has no multiply/divide, so these are done with shifts.
static uint32_t udiv(uint32_t n, uint32_t d)
{
    uint32_t q = 0, r = 0;
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) { r -= d; q |= 1u << i; }
    }
    return q;
}

static uint32_t mul100(uint32_t x)
{
    return (x << 6) + (x << 5) + (x << 2);      // 64x + 32x + 4x
}

// binary (0..9999) -> 4 BCD digits so the hex display reads as decimal
static uint32_t to_bcd4(uint32_t v)
{
    uint32_t out = 0;
    for (int shift = 0; shift < 16; shift += 4) {
        uint32_t q = udiv(v, 10);
        out |= (v - ((q << 3) + (q << 1))) << shift;
        v = q;
    }
    return out;
}

int main(void)
{
    uint32_t count = 0, led = 1, dir = 1;
    uint32_t last = CYCLES;
    uint32_t c0 = CYCLES, n0 = INSTRET, cpi_bcd = 0;

    LED = led;

    for (;;) {
        uint32_t btn    = BUTTON;
        uint32_t period = (btn & BTN_U) ? CORE_HZ / 40 : CORE_HZ / 10;

        if (btn & BTN_C)
            count = 0;

        if ((uint32_t)(CYCLES - last) >= period) {
            last += period;
            count++;

            led = dir ? (led << 1) : (led >> 1);
            if (led == 0x8000) dir = 0;
            if (led == 0x0001) dir = 1;
            LED = led;

            // CPI over the last tick
            uint32_t c1 = CYCLES, n1 = INSTRET;
            cpi_bcd = to_bcd4(udiv(mul100(c1 - c0), n1 - n0));
            c0 = c1; n0 = n1;
        }

        uint32_t low = (btn & BTN_D) ? cpi_bcd : (count & 0xFFFF);
        SEVENSEG = ((SWITCH & 0xFFFF) << 16) | low;
    }
}
