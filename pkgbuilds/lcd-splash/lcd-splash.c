/*
 * lcd-splash — fast ILI9341 boot splash for pi-Stomp
 *
 * Drives the 320x240 SPI LCD directly (spidev + lgpio) with no
 * Python/interpreter overhead.  Loads a raw RGB565-BE image (153600
 * bytes, pre-converted at build time), optionally overlays a text
 * message, and blits to the display.
 *
 * Usage: lcd-splash <image.rgb565> [message]
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <linux/spi/spidev.h>
#include <lgpio.h>

#include "font.h"

/* ── display constants ────────────────────────────────────── */

#define LCD_W           320
#define LCD_H           240
#define LCD_PIXELS      (LCD_W * LCD_H)
#define LCD_FB_SIZE     (LCD_PIXELS * 2)

#define SPI_DEVICE      "/dev/spidev0.0"
#define SPI_SPEED_HZ    80000000
#define SPI_MODE        SPI_MODE_0
#define SPI_BPW         8

#define DC_PIN          6           /* GPIO6 = data/command */
#define CS_PIN          8           /* GPIO8 = CE0 (active low) */

/* ILI9341 commands */
#define CMD_SLPOUT      0x11
#define CMD_DISPON      0x29
#define CMD_CASET       0x2A
#define CMD_PASET       0x2B
#define CMD_RAMWR       0x2C
#define CMD_MADCTL      0x36
#define CMD_PIXFMT      0x3A

/* MADCTL for landscape, BGR panel (MY=1, MX=1, MV=1, BGR=1) */
#define MADCTL_LANDSCAPE 0xE8

/* Text rendering — white in RGB565-BE */
#define MSG_COLOR       __builtin_bswap16(0xFFFF)
#define MSG_PAD_BOTTOM  16

/* Max bytes per spidev write() — kernel default bufsiz */
#define SPI_CHUNK       4096

/* Stamp file: presence means display is already initialised this boot */
#define INIT_STAMP      "/run/lcd.init"

/* ── globals ──────────────────────────────────────────────── */

static int spi_fd  = -1;
static int gpio_h  = -1;

/* ── SPI / GPIO helpers ───────────────────────────────────── */

static void cs_assert(void)   { lgGpioWrite(gpio_h, CS_PIN, 0); }
static void cs_release(void)  { lgGpioWrite(gpio_h, CS_PIN, 1); }
static void dc_command(void)  { lgGpioWrite(gpio_h, DC_PIN, 0); }
static void dc_data(void)     { lgGpioWrite(gpio_h, DC_PIN, 1); }

static void spi_write_chunk(const uint8_t *buf, size_t len)
{
    while (len > 0) {
        size_t n = len < SPI_CHUNK ? len : SPI_CHUNK;
        ssize_t r = write(spi_fd, buf, n);
        if (r < 0) {
            perror("spi write");
            return;
        }
        buf += r;
        len -= (size_t)r;
    }
}

static void send_cmd(uint8_t cmd)
{
    dc_command();
    cs_assert();
    write(spi_fd, &cmd, 1);
    cs_release();
}

static void send_data(const uint8_t *data, size_t len)
{
    dc_data();
    cs_assert();
    spi_write_chunk(data, len);
    cs_release();
}

static void send_data8(uint8_t val)
{
    send_data(&val, 1);
}

/* ── ILI9341 init ─────────────────────────────────────────── */

static void lcd_init(void)
{
    if (access(INIT_STAMP, F_OK) != 0) {
        /* First call this boot: wake display */
        send_cmd(CMD_SLPOUT);
        usleep(120000);
        send_cmd(CMD_DISPON);

        int fd = creat(INIT_STAMP, 0644);
        if (fd >= 0) close(fd);
    }

    /* Always set pixel format and orientation — other software
     * (e.g. adafruit driver) may have changed these. */
    send_cmd(CMD_PIXFMT);
    send_data8(0x55);
    send_cmd(CMD_MADCTL);
    send_data8(MADCTL_LANDSCAPE);
}

static void lcd_set_window(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1)
{
    send_cmd(CMD_CASET);
    uint8_t ca[4] = { x0 >> 8, x0 & 0xFF, x1 >> 8, x1 & 0xFF };
    send_data(ca, 4);

    send_cmd(CMD_PASET);
    uint8_t pa[4] = { y0 >> 8, y0 & 0xFF, y1 >> 8, y1 & 0xFF };
    send_data(pa, 4);
}

static void lcd_write_pixels(const uint16_t *px, size_t count)
{
    send_cmd(CMD_RAMWR);
    send_data((const uint8_t *)px, count * 2);
}

/* ── Image loading ────────────────────────────────────────── */

static uint16_t *load_image(const char *path)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) { perror(path); return NULL; }

    struct stat st;
    if (fstat(fd, &st) < 0) { perror(path); close(fd); return NULL; }

    if (st.st_size != LCD_FB_SIZE) {
        fprintf(stderr, "%s: expected %d bytes, got %ld\n",
                path, LCD_FB_SIZE, (long)st.st_size);
        close(fd);
        return NULL;
    }

    uint16_t *buf = malloc(LCD_FB_SIZE);
    size_t remaining = LCD_FB_SIZE;
    uint8_t *p = (uint8_t *)buf;
    while (remaining > 0) {
        ssize_t r = read(fd, p, remaining);
        if (r <= 0) { perror(path); free(buf); close(fd); return NULL; }
        p += r;
        remaining -= (size_t)r;
    }
    close(fd);
    return buf;
}

/* ── Text rendering (PSF bitmap font from font.h) ────────── */

static void render_char(uint16_t *fb, int px, int py, unsigned char ch)
{
    if (ch >= FONT_NUM_GLYPHS) return;

    const unsigned char *glyph = font_data[ch];
    int bytes_per_row = (FONT_WIDTH + 7) / 8;

    for (int row = 0; row < FONT_HEIGHT; row++) {
        for (int col = 0; col < FONT_WIDTH; col++) {
            int byte_idx = col / 8;
            int bit_idx  = 7 - (col % 8);
            if (glyph[row * bytes_per_row + byte_idx] & (1 << bit_idx)) {
                int x = px + col;
                int y = py + row;
                if (x >= 0 && x < LCD_W && y >= 0 && y < LCD_H)
                    fb[y * LCD_W + x] = MSG_COLOR;
            }
        }
    }
}

static void render_message(uint16_t *fb, const char *msg)
{
    int len = (int)strlen(msg);
    int text_w = len * FONT_WIDTH;
    int px = (LCD_W - text_w) / 2;
    int py = LCD_H - FONT_HEIGHT - MSG_PAD_BOTTOM;

    for (int i = 0; i < len; i++)
        render_char(fb, px + i * FONT_WIDTH, py, (unsigned char)msg[i]);
}

/* ── Hardware setup ───────────────────────────────────────── */

static int open_spi(void)
{
    int fd = open(SPI_DEVICE, O_RDWR);
    if (fd < 0) { perror(SPI_DEVICE); return -1; }

    uint8_t  mode = SPI_MODE;
    uint8_t  bpw  = SPI_BPW;
    uint32_t speed = SPI_SPEED_HZ;

    ioctl(fd, SPI_IOC_WR_MODE, &mode);
    ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bpw);
    ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed);

    return fd;
}

static int open_gpio(void)
{
    /* Pi 5 GPIOs are on gpiochip4 (RP1), Pi 3/4 on gpiochip0 */
    int h = lgGpiochipOpen(4);
    if (h < 0)
        h = lgGpiochipOpen(0);
    if (h < 0) {
        fprintf(stderr, "lgGpiochipOpen: %s\n", lguErrorText(h));
        return -1;
    }
    int rc = lgGpioClaimOutput(h, 0, DC_PIN, 0);
    if (rc < 0) {
        fprintf(stderr, "lgGpioClaimOutput(%d): %s\n", DC_PIN, lguErrorText(rc));
        lgGpiochipClose(h);
        return -1;
    }
    rc = lgGpioClaimOutput(h, 0, CS_PIN, 1);  /* CS idle high */
    if (rc < 0) {
        fprintf(stderr, "lgGpioClaimOutput(%d): %s\n", CS_PIN, lguErrorText(rc));
        lgGpiochipClose(h);
        return -1;
    }
    return h;
}

/* ── main ─────────────────────────────────────────────────── */

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "usage: lcd-splash <image.rgb565> [message]\n");
        return 1;
    }

    const char *image_path = argv[1];
    const char *message    = argc > 2 ? argv[2] : NULL;

    /* Open hardware */
    spi_fd = open_spi();
    if (spi_fd < 0) return 1;

    gpio_h = open_gpio();
    if (gpio_h < 0) { close(spi_fd); return 1; }

    /* Initialise LCD if first time this boot */
    lcd_init();

    /* Load pre-converted framebuffer */
    uint16_t *fb = load_image(image_path);
    if (!fb) { lgGpiochipClose(gpio_h); close(spi_fd); return 1; }

    /* Overlay text */
    if (message && message[0])
        render_message(fb, message);

    /* Blit */
    lcd_set_window(0, 0, LCD_W - 1, LCD_H - 1);
    lcd_write_pixels(fb, LCD_PIXELS);

    /* Cleanup */
    free(fb);
    lgGpiochipClose(gpio_h);
    close(spi_fd);
    return 0;
}
