#include <stdio.h>
#include "pico/stdlib.h"
#include "FreeRTOS.h"
#include "task.h"
#include "luat_base.h"

#define LUAT_HEAP_SIZE (64*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

void vTaskCode( void * pvParameters )
{
    bpool(luavm_heap,LUAT_HEAP_SIZE);
	luat_main();
    while(1)
    {
        printf("Hello, world!\n");
        vTaskDelay(1000);
    }
}

int main() {
stdio_init_all();
BaseType_t xReturned;
TaskHandle_t xHandle = NULL;
/* Create the task, storing the handle. */
    xReturned = xTaskCreate(
                    vTaskCode,       /* Function that implements the task. */
                    "task",          /* Text name for the task. */
                    4096,             /* Stack size in words, not bytes. */
                    ( void * ) 1,    /* Parameter passed into the task. */
                    tskIDLE_PRIORITY,/* Priority at which the task is created. */
                    &xHandle );

    vTaskStartScheduler();
    while(1)
    {
        configASSERT(0);
    }

}
