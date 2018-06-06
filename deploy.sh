#!/bin/bash

# rsync site to server
rsync -ravz --delete build/* un@nbf01.opsserver.ch:www/