/**
 *  @filename   :   epdif.c
 *  @brief      :   Implements EPD interface functions
 *                  Users have to implement all the functions in epdif.cpp
 *  @author     :   Yehui from Waveshare
 *
 *  Copyright (C) Waveshare     July 7 2017
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documnetation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to  whom the Software is
 * furished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS OR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "epdif.h"
#include "luat_gpio.h"
#include "luat_spi.h"

//#include "main.h"

// #define SPI_CS_GPIO_Port  0
// #define RST_GPIO_Port     0
// #define DC_GPIO_Port      0
// #define BUSY_GPIO_Port    0


// #define BUSY_Pin          (18)
// #define RST_Pin           (7)
// #define DC_Pin            (9)
// #define SPI_CS_Pin        (16)

// #define SPI_ID            (0)

//extern SPI_HandleTypeDef hspi1;

// EPD_Pin epd_cs_pin = {
//   SPI_CS_GPIO_Port
// };

// EPD_Pin epd_rst_pin = {
//   RST_GPIO_Port
// };

// EPD_Pin epd_dc_pin = {
//   DC_GPIO_Port
// };

// EPD_Pin epd_busy_pin = {
//   BUSY_GPIO_Port
// };

EPD_Pin pins[4];

void EpdDigitalWriteCallback(int pin_num, int value) {
  if (value == HIGH) {
  //  HAL_GPIO_WritePin((GPIO_TypeDef*)pins[pin_num].port, pins[pin_num].pin, GPIO_PIN_SET);
    luat_gpio_set(pins[pin_num].port, Luat_GPIO_HIGH);
  } else {
  //  HAL_GPIO_WritePin((GPIO_TypeDef*)pins[pin_num].port, pins[pin_num].pin, GPIO_PIN_RESET);
    luat_gpio_set(pins[pin_num].port, Luat_GPIO_LOW);
  }


  
}

int EpdDigitalReadCallback(int pin_num) {
  // if (HAL_GPIO_ReadPin(pins[pin_num].port, pins[pin_num].pin) == GPIO_PIN_SET) {
  //   return HIGH;
  // } else {
  //   return LOW;
  // }

  if (luat_gpio_get(pins[pin_num].port) == Luat_GPIO_HIGH) {
    return HIGH;
  } else {
    return LOW;
  }
}

void EpdDelayMsCallback(unsigned int delaytime) {
 // HAL_Delay(delaytime);
    while(delaytime--)
    {
        luat_timer_us_delay(1000);
    }
}

void EpdSpiTransferCallback(unsigned char data) {
  // HAL_GPIO_WritePin((GPIO_TypeDef*)pins[CS_PIN].port, pins[CS_PIN].pin, GPIO_PIN_RESET);
  // HAL_SPI_Transmit(&hspi1, &data, 1, 1000);
  // HAL_GPIO_WritePin((GPIO_TypeDef*)pins[CS_PIN].port, pins[CS_PIN].pin, GPIO_PIN_SET);

  luat_gpio_set(pins[CS_PIN].port, Luat_GPIO_LOW);
  luat_spi_send(EPD_SPI_ID, (char *)&data, 1);
  luat_gpio_set(pins[CS_PIN].port, Luat_GPIO_HIGH);

}

int EpdInitCallback(void) {
  pins[CS_PIN].port = EPD_CS_PIN;
  pins[RST_PIN].port = EPD_RST_PIN;
  pins[DC_PIN].port = EPD_DC_PIN;
  pins[BUSY_PIN].port = EPD_BUSY_PIN;
  
  return 0;
}

