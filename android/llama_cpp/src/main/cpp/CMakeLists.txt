cmake_minimum_required(VERSION 3.22.1)

project("ai-chat" LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(LLAMA_SRC "${CMAKE_CURRENT_LIST_DIR}/../../../native")
# Bundle llama.cpp and the CPU ggml backend into libai-chat.so. Leaving
# BUILD_SHARED_LIBS enabled makes the backend a separate plugin, which is not
# discovered from Android's app-native library directory at runtime.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
add_subdirectory("${LLAMA_SRC}" build-llama)

add_library(ai-chat SHARED ai_chat.cpp)
target_include_directories(ai-chat PRIVATE
    "${LLAMA_SRC}"
    "${LLAMA_SRC}/common"
    "${LLAMA_SRC}/include"
    "${LLAMA_SRC}/ggml/include"
    "${LLAMA_SRC}/ggml/src"
)
target_link_libraries(ai-chat llama llama-common android log)
