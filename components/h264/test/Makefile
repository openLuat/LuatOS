CC      = gcc
CFLAGS  = -Wall -Wextra -g -O0 -I../include -I../src -I.
SRCS    = test_main.c \
          test_bitstream.c \
          test_sps_pps.c \
          test_cavlc.c \
          test_integration.c \
          ../src/h264_tables.c \
          ../src/h264_bitstream.c \
          ../src/h264_nalu.c \
          ../src/h264_sps_pps.c \
          ../src/h264_cavlc.c \
          ../src/h264_idct.c \
          ../src/h264_intra.c \
          ../src/h264_inter.c \
          ../src/h264_deblock.c \
          ../src/h264_slice.c \
          ../src/h264_decoder.c
TARGET  = test_h264

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) -o $@ $^ -lm

clean:
	rm -f $(TARGET) *.o

.PHONY: all clean
