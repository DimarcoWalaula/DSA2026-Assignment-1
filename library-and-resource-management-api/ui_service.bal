import ballerina/http;
import ballerina/io;

// ---------------------------------------------------------------------------
// Static hosting for the bonus browser console.
//
// It shares the listener with the REST API so the page is served from the
// same origin and can call `/library/...` directly with `fetch`, with no CORS
// gymnastics needed.
//
//   http://localhost:8080/         -> staff console
//   http://localhost:8080/library  -> REST API
//
// The page is read from disk relative to the working directory, so start the
// service from inside the `library-and-resource-management-api` package directory.
// ---------------------------------------------------------------------------

const string CONSOLE_FILE = "resources/index.html";

service / on apiListener {

    resource function get .() returns http:Response|http:InternalServerError {
        return renderConsole();
    }

    resource function get console() returns http:Response|http:InternalServerError {
        return renderConsole();
    }
}

isolated function renderConsole() returns http:Response|http:InternalServerError {
    string|io:Error page = io:fileReadString(CONSOLE_FILE);
    if page is io:Error {
        http:InternalServerError serverError = {
            body: {
                code: "UI_UNAVAILABLE",
                message: "Could not read " + CONSOLE_FILE
                        + ". Start the service from inside the library-and-resource-management-api directory."
            }
        };
        return serverError;
    }
    http:Response response = new;
    response.setTextPayload(page, "text/html");
    return response;
}
