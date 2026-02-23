#ifndef THREADING_ALT_H
#define THREADING_ALT_H

#include <uv.h>

typedef struct
{
  uv_mutex_t Mutex;

} mbedtls_platform_mutex_t;

typedef struct
{
  uv_cond_t Condition;

} mbedtls_platform_condition_variable_t;

#endif /* THREADING_ALT_H */