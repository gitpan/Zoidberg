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
			[ qr/(?<![<>])&/ , 'EOS_BG' ],
			[ '==>',   'XFW'  ],
			[ '<==',   'XBW'  ],
	        ],
	},
	word_gram => qr/\s/,
};
