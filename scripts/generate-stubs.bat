@echo off
REM --------------------------------------------------------------------------
REM Generates the Ballerina gRPC stub (rental_pb.bal) for the Question 2 server
REM and client from proto\rental.proto. Run once after cloning.
REM
REM   scripts\generate-stubs.bat
REM --------------------------------------------------------------------------
setlocal
set ROOT=%~dp0..
set PROTO=%ROOT%\proto\rental.proto

where bal >nul 2>nul
if errorlevel 1 (
    echo Ballerina ^("bal"^) is not on the PATH. Install Swan Lake from https://ballerina.io/downloads/
    exit /b 1
)

REM Recent Swan Lake distributions ship the gRPC code generator as a separate
REM Ballerina tool rather than a built-in subcommand, so it has to be pulled
REM once before "bal grpc" works.
call bal grpc --help >nul 2>nul
if errorlevel 1 (
    echo The 'grpc' Ballerina tool is not installed yet - pulling it now ...
    call bal tool pull grpc
    if errorlevel 1 (
        echo Failed to pull the grpc tool. Check your network connection and try again.
        exit /b 1
    )
)

echo Generating stub for the server ...
call bal grpc --input "%PROTO%" --output "%ROOT%\rental-accommodation-server"
if errorlevel 1 (
    echo Failed to generate the server stub.
    exit /b 1
)

echo Generating stub for the client ...
call bal grpc --input "%PROTO%" --output "%ROOT%\rental-accommodation-client"
if errorlevel 1 (
    echo Failed to generate the client stub.
    exit /b 1
)

if not exist "%ROOT%\rental-accommodation-server\rental_pb.bal" (
    echo ERROR: expected stub was not created in rental-accommodation-server
    exit /b 1
)
if not exist "%ROOT%\rental-accommodation-client\rental_pb.bal" (
    echo ERROR: expected stub was not created in rental-accommodation-client
    exit /b 1
)

echo.
echo Done. Both Question 2 packages now contain rental_pb.bal.
endlocal
