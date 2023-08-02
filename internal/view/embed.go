package views

import "embed"

//go:embed assets/*
var Assets embed.FS

//go:embed *.html
var Templates embed.FS

//go:embed manifest.webmanifest
var Manifest string

//go:embed sw.js
var ServiceWorker string

//go:embed robots.txt
var Robots string
