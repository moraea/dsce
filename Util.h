
@import Foundation;

inline void trace(NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *message =
      [NSString.alloc initWithFormat:format arguments:args].autorelease;
  va_end(args);

  printf("\e[%dm%s\e[0m\n", 31 + DSCE_VERSION % 6, message.UTF8String);
}

extern BOOL flagPad;