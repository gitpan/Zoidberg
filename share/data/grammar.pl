{
	_base_gram => {
	        esc => '\\',
	        nests => {
	                '{' => '}',
			'(' => ')',
	        },
	        quotes => {
	                '"' => '"',
	                "'" => "'",
			'`' => '`',
	        },
	},
	script_gram => {
	        tokens => [
			[ ';',     'EOS'  ],
			[ qr/\n/,  'EOL'  ],
	                [ '&&',    'AND'  ],
			[ '||',    'OR'   ],
	                [ '|' ,    '_CUT' ],
			[ qr/(?<![<>])&/ , 'BGS' ],
			[ '==>',   'XFW'  ],
			[ '<==',   'XBW'  ],
	        ],
		no_esc_rm => 1,
	},
	word_gram => qr/\s+/,
};