# Overall Plan

I'd like a personal calculator app for Mac Desktop and iOS (iPhone). The name of it will be Calcsmith. Build this as a native SwiftUI app targeting both iOS and macOS from one codebase (a Swift Package with shared model/logic, plus thin platform-specific UI). The default interface is a scientific calculator, with the answers displayed in engineering notation (i.e. 1e-3 is m (milli), 1e-6 is μ, etc.). For the desktop app, ensure I can type the math right away via keyboard, as well as have buttons to press. I'd like there to be a button to switch modes to see a list of equations I can select and then enter the variables to calculate. Also, like in analog_engineer_assistant, have it that I can TAB to change the subject of the formula. The list should be searchable as well. For the list of equations, please refer to my previous analog_engineer_assistant app @/Users/douglassmurray/Repos/analog_engineer_assistant.

## Architecture
Build this as a native SwiftUI app targeting both iOS and macOS from one codebase (a Swift Package with shared model/logic, plus thin platform-specific UI).

## Interface
The display should be in engineering notation, i.e. 1e-3 is m (milli), 1e-6 is μ, etc.).

### Desktop app
Ensure I can type the math right away via keyboard, as well as have buttons to press.

## Equations list
Please refer to my previous analog_engineer_assistant app @/Users/douglassmurray/Repos/analog_engineer_assistant. 
