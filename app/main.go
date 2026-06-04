package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
)

type Response struct {
	Message string `json:"message"`
	Tenant  string `json:"tenant"`
	Version string `json:"version"`
}

func main() {
	tenant := os.Getenv("TENANT_NAME")
	if tenant == "" {
		tenant = "unknown"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(Response{
			Message: "GitOps Platform API",
			Tenant:  tenant,
			Version: "1.0.0",
		})
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	fmt.Println("Server starting on :8080")
	http.ListenAndServe(":8080", nil)
}
