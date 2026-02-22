/*
 * lcd-splash — fast ILI9341 boot splash for pi-Stomp
 *
 * Drives the 320x240 SPI LCD directly (spidev + lgpio) with no
 * Python/interpreter overhead.  Loads a PNG, optionally overlays a
 * text message at the bottom, and blits to the display.
 *
 * Usage: lcd-splash <image.png> [message]
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
#include <linux/spi/spidev.h>
#include <lgpio.h>
#include <png.h>

#include "font.h"

/* ── display constants ────────────────────────────────────── */

#define LCD_W           320
#define LCD_H           240
#define LCD_PIXELS      (LCD_W * LCD_H)

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

/* MADCTL for rotation=90 (landscape, BGR panel) */
#define MADCTL_ROT270   0xE8

/* Text rendering */
#define MSG_COLOR_R     255
#define MSG_COLOR_G     255
#define MSG_COLOR_B     255
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
    if (access(INIT_STAMP, F_OK) == 0) return;

    send_cmd(CMD_SLPOUT);
    usleep(120000);

    /* 16-bit colour (RGB565) */
    send_cmd(CMD_PIXFMT);
    send_data8(0x55);

    /* Landscape orientation, BGR subpixels */
    send_cmd(CMD_MADCTL);
    send_data8(MADCTL_ROT270);

    /* Display on */
    send_cmd(CMD_DISPON);

    int fd = creat(INIT_STAMP, 0644);
    if (fd >= 0) close(fd);
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

/* ── PNG loading ──────────────────────────────────────────── */

/* Returns malloc'd RGB888 buffer (3 bytes/pixel), or NULL on error. */
static uint8_t *load_png(const char *path, int *w, int *h)
{
    FILE *fp = fopen(path, "rb");
    if (!fp) { perror(path); return NULL; }

    png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING,
                                             NULL, NULL, NULL);
    png_infop info = png_create_info_struct(png);
    if (setjmp(png_jmpbuf(png))) {
        png_destroy_read_struct(&png, &info, NULL);
        fclose(fp);
        return NULL;
    }

    png_init_io(png, fp);
    png_read_info(png, info);

    *w = (int)png_get_image_width(png, info);
    *h = (int)png_get_image_height(png, info);

    /* Normalise to 8-bit RGB */
    png_byte color_type = png_get_color_type(png, info);
    png_byte bit_depth  = png_get_bit_depth(png, info);

    if (bit_depth == 16)
        png_set_strip_16(png);
    if (color_type == PNG_COLOR_TYPE_PALETTE)
        png_set_palette_to_rgb(png);
    if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8)
        png_set_expand_gray_1_2_4_to_8(png);
    if (png_get_valid(png, info, PNG_INFO_tRNS))
        png_set_tRNS_to_alpha(png);
    if (color_type == PNG_COLOR_TYPE_RGBA ||
        color_type == PNG_COLOR_TYPE_GRAY_ALPHA)
        png_set_strip_alpha(png);
    if (color_type == PNG_COLOR_TYPE_GRAY ||
        color_type == PNG_COLOR_TYPE_GRAY_ALPHA)
        png_set_gray_to_rgb(png);

    png_read_update_info(png, info);

    size_t rowbytes = png_get_rowbytes(png, info);
    uint8_t *buf = malloc((size_t)(*h) * rowbytes);
    png_bytep *rows = malloc(sizeof(png_bytep) * (size_t)(*h));
    for (int y = 0; y < *h; y++)
        rows[y] = buf + y * rowbytes;

    png_read_image(png, rows);
    png_read_end(png, NULL);
    png_destroy_read_struct(&png, &info, NULL);
    free(rows);
    fclose(fp);
    return buf;
}

/* ── Fit image into LCD_W x LCD_H (letterbox, black bars) ── */

static void fit_to_lcd(const uint8_t *src, int sw, int sh,
                       uint8_t *dst /* LCD_W*LCD_H*3 */)
{
    memset(dst, 0, LCD_W * LCD_H * 3);

    /* If image is exactly 320x240, just copy */
    if (sw == LCD_W && sh == LCD_H) {
        memcpy(dst, src, LCD_W * LCD_H * 3);
        return;
    }

    /* Compute scale to fit, nearest-neighbour */
    float sx = (float)LCD_W / sw;
    float sy = (float)LCD_H / sh;
    float scale = sx < sy ? sx : sy;

    int dw = (int)(sw * scale);
    int dh = (int)(sh * scale);
    int ox = (LCD_W - dw) / 2;
    int oy = (LCD_H - dh) / 2;

    for (int y = 0; y < dh; y++) {
        int srcy = (int)(y / scale);
        if (srcy >= sh) srcy = sh - 1;
        for (int x = 0; x < dw; x++) {
            int srcx = (int)(x / scale);
            if (srcx >= sw) srcx = sw - 1;
            int si = (srcy * sw + srcx) * 3;
            int di = ((oy + y) * LCD_W + (ox + x)) * 3;
            dst[di]     = src[si];
            dst[di + 1] = src[si + 1];
            dst[di + 2] = src[si + 2];
        }
    }
}

/* ── Text rendering (PSF bitmap font from font.h) ────────── */

static void render_char(uint8_t *fb, int px, int py, unsigned char ch)
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
                if (x >= 0 && x < LCD_W && y >= 0 && y < LCD_H) {
                    int off = (y * LCD_W + x) * 3;
                    fb[off]     = MSG_COLOR_R;
                    fb[off + 1] = MSG_COLOR_G;
                    fb[off + 2] = MSG_COLOR_B;
                }
            }
        }
    }
}

static void render_message(uint8_t *fb, const char *msg)
{
    int len = (int)strlen(msg);
    int text_w = len * FONT_WIDTH;
    int px = (LCD_W - text_w) / 2;
    int py = LCD_H - FONT_HEIGHT - MSG_PAD_BOTTOM;

    for (int i = 0; i < len; i++) {
        render_char(fb, px + i * FONT_WIDTH, py, (unsigned char)msg[i]);
    }
}

/* ── RGB888 → RGB565 (big-endian for SPI) ─────────────────── */

static void rgb888_to_rgb565be(const uint8_t *rgb, uint16_t *out, size_t npix)
{
    for (size_t i = 0; i < npix; i++) {
        uint8_t r = rgb[i * 3];
        uint8_t g = rgb[i * 3 + 1];
        uint8_t b = rgb[i * 3 + 2];
        uint16_t c = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
        out[i] = __builtin_bswap16(c);   /* SPI sends MSB first */
    }
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
        fprintf(stderr, "usage: lcd-splash <image.png> [message]\n");
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

    /* Load image */
    int pw, ph;
    uint8_t *png_rgb = load_png(image_path, &pw, &ph);
    if (!png_rgb) { close(spi_fd); lgGpiochipClose(gpio_h); return 1; }

    /* Fit to LCD */
    uint8_t *fb = malloc(LCD_W * LCD_H * 3);
    fit_to_lcd(png_rgb, pw, ph, fb);
    free(png_rgb);

    /* Overlay text */
    if (message && message[0])
        render_message(fb, message);

    /* Convert to RGB565 */
    uint16_t *px = malloc(LCD_PIXELS * 2);
    rgb888_to_rgb565be(fb, px, LCD_PIXELS);
    free(fb);

    /* Blit */
    lcd_set_window(0, 0, LCD_W - 1, LCD_H - 1);
    lcd_write_pixels(px, LCD_PIXELS);

    /* Cleanup */
    free(px);
    lgGpiochipClose(gpio_h);
    close(spi_fd);
    return 0;
}
