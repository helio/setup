#!/bin/bash

# rsync site to server
rsync -ravz --delete build/* unidling@nbf01.opsserver.ch:www/