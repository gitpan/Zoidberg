#!/usr/bin/env zoid
;->{config}{zoid_naked}=1;{->buffer->set_string('Try out some cool stuff, then press Ctrl-d')}i;{->main_loop};{->print("Hahaha ... mere
        mortal:0",'warning')};{->buffer->set_string('_5 cd ..')};{$self->parse($self->buffer->read)};{->buffer->set_string('_5 back')}
{->parse(->buffer->read)}
{->buffer->set_string('select id from tbl where ->{key} = ->{_}')}
{->parse($self->buffer->read)}
{->buffer->set_string('c/printf("Inline::C rocks")/')}
{->parse(->buffer->read)}
{->print('And now for something completely different...')}


