# lvgl-sdl
![Linux](https://github.com/Ryzee119/nxdk-lvgl/workflows/Linux/badge.svg) ![Windows](https://github.com/Ryzee119/nxdk-lvgl/workflows/Windows/badge.svg) ![Xbox](https://github.com/Ryzee119/nxdk-lvgl/workflows/Xbox/badge.svg)

A crossplatform SDL wrapper for the Light and Versatile Graphics Library https://lvgl.io/.
* SDL2 video backend.
* SDL gamecontroller and keyboard input driver.
* Filesystem driver uses `stdio.h` for file access.
* Supports directory listings with winapi for Windows, and posix for Linux.
* Cross platform. Currently supports Windows, Linux and Original Xbox!

# Include in your project
In your git repo:
* `git submodule add https://github.com/Ryzee119/lvgl-sdl.git`
* `cd lvgl-sdl && git submodule init && git submodule update`
* See the example [CMakeLists.txt](./example/CMakeLists.txt) for the required directories to include in your build system.
* Copy `lv_conf.h` from `lvgl-sdl` folder and place it into your project. Configure CMakeList/Makefile to set LV_CONF_PATH to point to your `lv_conf.h
* See the [example](./example/example.c) for usage and required initialisation functions etc.

# Or build the examples
* Pre-built binaries can be downloaded from the [Actions](https://github.com/Ryzee119/lvgl-sdl/actions) page as artifacts. These just run the default example.
* For manual compiling you can edit `lv_ex_conf.h` to change which demo to run.
* Remember to clone this repo recusively i.e `git clone https://github.com/Ryzee119/lvgl-sdl.git --recursive`.

## Build (Linux)
```
apt install libsdl2-dev
cd example/
mkdir build
cd build
cmake ..
cmake --build .
./lvgl_example
```

## Build (Windows)
Install MYSYS2, then from a mingw64 environment:
```
pacman -S mingw-w64-x86_64-make \
          mingw-w64-x86_64-cmake \
          mingw-w64-x86_64-gcc \
          mingw-w64-x86_64-SDL2
cd example/
mkdir build && cd build
cmake .. -G "MinGW Makefiles"
cmake --build .
./lvgl_example.exe
```

## Build (Original Xbox)
Setup and install [nxdk](https://github.com/XboxDev/nxdk/).
```
Run the activate script in nxdk/bin
cd example/
make -f Makefile.nxdk
```

## Images
![example1](./images/example1.png)

