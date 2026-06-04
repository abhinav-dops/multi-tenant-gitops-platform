package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
)

type Response struct {
	Message string `json:"message"`
	Tenant  string `json:"tenant"`
	Version string `json:"version"`
}

func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s %s", r.Method, r.URL.Path, r.RemoteAddr)
		next(w, r)
	}
}

func main() {
	tenant := os.Getenv("TENANT_NAME")
	if tenant == "" {
		tenant = "unknown"
	}

	http.HandleFunc("/", loggingMiddleware(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(Response{
			Message: "GitOps Platform API",
			Tenant:  tenant,
			Version: "1.0.0",
		})
	}))

	http.HandleFunc("/health", loggingMiddleware(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	}))

	log.Printf("Server starting on :8080 | tenant=%s", tenant)
	http.ListenAndServe(":8080", nil)
}
