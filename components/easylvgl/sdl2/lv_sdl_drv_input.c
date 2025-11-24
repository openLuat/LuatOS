/* MIT License
 * 
 * Copyright (c) [2020] [Ryan Wendland]
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
#include "luat_base.h"
#ifdef LUAT_USE_LVGL_SDL2
#include <stdio.h>
#include <SDL2/SDL.h>

#include "../lvgl9/lvgl.h"
#include "../lvgl9/lv_conf.h"
#include "lv_sdl_drv_input.h"

static quit_event_t quit_event = false;

/**
 * SDL2 输入设备读取回调（LVGL 9 格式）
 * LVGL 9 的读取回调签名：void read(lv_indev_t *indev, lv_indev_data_t *data)
 */
static void sdl_input_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    (void)indev;
    
    data->key = 0;
    data->state = LV_INDEV_STATE_RELEASED;
    data->point.x = 0;
    data->point.y = 0;
    data->continue_reading = false;

    static SDL_Event e;
    if (SDL_PollEvent(&e))
    {
        data->continue_reading = true;  // 还有更多事件需要处理
        
        if (e.type == SDL_MOUSEBUTTONDOWN) {
            if (e.button.button == SDL_BUTTON_LEFT) {
                data->state = LV_INDEV_STATE_PRESSED;
                data->point.x = e.button.x;
                data->point.y = e.button.y;
            }
        }
        else if (e.type == SDL_MOUSEBUTTONUP) {
            if (e.button.button == SDL_BUTTON_LEFT) {
                data->state = LV_INDEV_STATE_RELEASED;
                data->point.x = e.button.x;
                data->point.y = e.button.y;
            }
        }
        else if (e.type == SDL_MOUSEMOTION) {
            // 鼠标移动事件
            if (e.motion.state & SDL_BUTTON_LMASK) {
                data->state = LV_INDEV_STATE_PRESSED;
                data->point.x = e.motion.x;
                data->point.y = e.motion.y;
            } else {
                data->state = LV_INDEV_STATE_RELEASED;
                data->point.x = e.motion.x;
                data->point.y = e.motion.y;
            }
        }

        if (e.type == SDL_CONTROLLERBUTTONDOWN || e.type == SDL_KEYDOWN)
            data->state = LV_INDEV_STATE_PRESSED;
        if (e.type == SDL_CONTROLLERBUTTONUP || e.type == SDL_KEYUP)
            data->state = LV_INDEV_STATE_RELEASED;

        if (e.type == SDL_CONTROLLERDEVICEADDED)
            SDL_GameControllerOpen(e.cdevice.which);
        if (e.type == SDL_CONTROLLERDEVICEREMOVED)
            SDL_GameControllerClose(SDL_GameControllerFromInstanceID(e.cdevice.which));

        //Gamecontroller event
        if (e.type == SDL_CONTROLLERBUTTONDOWN || e.type == SDL_CONTROLLERBUTTONUP)
        {
            switch (e.cbutton.button)
            {
                case SDL_CONTROLLER_BUTTON_A:             data->key = LV_KEY_ENTER; break;
                case SDL_CONTROLLER_BUTTON_B:             data->key = LV_KEY_ESC; break;
                case SDL_CONTROLLER_BUTTON_X:             data->key = LV_KEY_BACKSPACE; break;
                case SDL_CONTROLLER_BUTTON_Y:             data->key = LV_KEY_HOME; break;
                case SDL_CONTROLLER_BUTTON_BACK:          data->key = LV_KEY_PREV; break;
                case SDL_CONTROLLER_BUTTON_START:         data->key = LV_KEY_NEXT; break;
                case SDL_CONTROLLER_BUTTON_LEFTSTICK:     data->key = LV_KEY_PREV; break;
                case SDL_CONTROLLER_BUTTON_RIGHTSTICK:    data->key = LV_KEY_NEXT; break;
                case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  data->key = LV_KEY_PREV; break;
                case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: data->key = LV_KEY_NEXT; break;
                case SDL_CONTROLLER_BUTTON_DPAD_UP:       data->key = LV_KEY_UP; break;
                case SDL_CONTROLLER_BUTTON_DPAD_DOWN:     data->key = LV_KEY_DOWN; break;
                case SDL_CONTROLLER_BUTTON_DPAD_LEFT:     data->key = LV_KEY_LEFT; break;
                case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:    data->key = LV_KEY_RIGHT; break;
            }
        }
        
        //Keyboard event
        if (e.type == SDL_KEYDOWN || e.type == SDL_KEYUP)
        {
            switch (e.key.keysym.sym)
            {
                case SDLK_ESCAPE:    data->key = LV_KEY_ESC; break;
                case SDLK_BACKSPACE: data->key = LV_KEY_BACKSPACE; break;
                case SDLK_HOME:      data->key = LV_KEY_HOME; break;
                case SDLK_RETURN:    data->key = LV_KEY_ENTER; break;
                case SDLK_PAGEDOWN:  data->key = LV_KEY_PREV; break;
                case SDLK_TAB:       data->key = LV_KEY_NEXT; break;
                case SDLK_PAGEUP:    data->key = LV_KEY_NEXT; break;
                case SDLK_UP:        data->key = LV_KEY_UP; break;
                case SDLK_DOWN:      data->key = LV_KEY_DOWN; break;
                case SDLK_LEFT:      data->key = LV_KEY_LEFT; break;
                case SDLK_RIGHT:     data->key = LV_KEY_RIGHT; break;
            }
        }

        //Quit event
        if((e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_CLOSE) ||
            e.type == SDL_QUIT) {
            quit_event = true;
            exit(0);
        }
    }
    else
    {
        data->continue_reading = false;  // 没有更多事件
    }
}

quit_event_t get_quit_event(void)
{
    return quit_event;
}

void set_quit_event(quit_event_t quit)
{
    quit_event = quit;
}

/**
 * 初始化 SDL2 输入设备驱动（LVGL 9.4）
 */
lv_indev_t *lv_sdl_init_input(void)
{
    if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0)
        printf("SDL_InitSubSystem failed: %s\n", SDL_GetError());

    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    for (int i = 0; i < SDL_NumJoysticks(); i++)
    {
        SDL_GameControllerOpen(i);
    }

    // 创建键盘输入设备
    lv_indev_t *keypad_indev = lv_indev_create();
    if (keypad_indev != NULL) {
        lv_indev_set_type(keypad_indev, LV_INDEV_TYPE_KEYPAD);
        lv_indev_set_read_cb(keypad_indev, sdl_input_read);
    }

    // 创建指针输入设备（鼠标/触摸）
    lv_indev_t *pointer_indev = lv_indev_create();
    if (pointer_indev != NULL) {
        lv_indev_set_type(pointer_indev, LV_INDEV_TYPE_POINTER);
        lv_indev_set_read_cb(pointer_indev, sdl_input_read);
    }

    return pointer_indev;  // 返回指针设备作为主要输入设备
}

void lv_sdl_deinit_input(void)
{
    SDL_GameControllerClose(0);
    SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
}

#endif
