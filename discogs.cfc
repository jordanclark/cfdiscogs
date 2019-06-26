component {
	cfprocessingdirective( preserveCase=true );

	function init(
		required string apiKey
	,	required string apiSecret
	,	required string token
	,	string apiUrl= "https://api.discogs.com"
	,	string userAgent= "CFML API Agent 0.1"
	,	numeric throttle= 250
	,	numeric httpTimeOut= 60
	,	boolean debug= ( request.debug ?: false )
	) {
		this.apiKey= arguments.apiKey;
		this.apiSecret= arguments.apiSecret;
		this.token= arguments.token;
		this.apiUrl= arguments.apiUrl;
		this.userAgent= arguments.userAgent;
		this.httpTimeOut= arguments.httpTimeOut;
		this.throttle= arguments.throttle;
		this.lastRequest= server.discogs_lastRequest ?: 0;
		this.orderStatusOptions= [
			'All'
		,	'New Order'
		,	'Buyer Contacted'
		,	'Invoice Sent'
		,	'Payment Pending'
		,	'Payment Received'
		,	'Shipped'
		,	'Merged'
		,	'Order Changed'
		,	'Refund Sent'
		,	'Cancelled'
		,	'Cancelled (Non-Paying Buyer)'
		,	'Cancelled (Item Unavailable)'
		,	'Cancelled (Per Buyer''s Request)'
		,	'Cancelled (Refund Received)'
		];
		return this;
	}

	function debugLog(required input) {
		if ( structKeyExists( request, "log" ) && isCustomFunction( request.log ) ) {
			if ( isSimpleValue( arguments.input ) ) {
				request.log( "Discogs: " & arguments.input );
			} else {
				request.log( "Discogs: (complex type)" );
				request.log( arguments.input );
			}
		} else if( this.debug ) {
			cftrace( text=( isSimpleValue( arguments.input ) ? arguments.input : "" ), var=arguments.input, category="Discogs", type="information" );
		}
		return;
	}

	struct function apiRequest(required string api) {
		if ( find( "{token}", arguments.api ) ) {
			arguments.api= replace( arguments.api, "{token}", this.token );
		} else {
			arguments[ "key" ]= this.apiKey;
			arguments[ "secret" ]= this.apiSecret;
		}
		var http= {};
		var item= "";
		var out= {
			args= arguments
		,	success= false
		,	error= ""
		,	status= ""
		,	statusCode= 0
		,	response= ""
		,	verb= listFirst( arguments.api, " " )
		,	requestUrl= this.apiUrl
		,	data= {}
		,	delay= 0
		};
		out.requestUrl &= listRest( out.args.api, " " );
		structDelete( out.args, "api" );
		// replace {var} in url 
		for ( item in out.args ) {
			// strip NULL values 
			if ( isNull( out.args[ item ] ) ) {
				structDelete( out.args, item );
			} else if ( isSimpleValue( arguments[ item ] ) && arguments[ item ] == "null" ) {
				arguments[ item ]= javaCast( "null", 0 );
			} else if ( findNoCase( "{#item#}", out.requestUrl ) ) {
				out.requestUrl= replaceNoCase( out.requestUrl, "{#item#}", out.args[ item ], "all" );
				structDelete( out.args, item );
			}
		}
		if ( out.verb == "GET" ) {
			out.requestUrl &= this.structToQueryString( out.args, out.requestUrl, true );
		} else if ( !structIsEmpty( out.args ) ) {
			out.body= serializeJSON( out.args );
		}
		this.debugLog( "API: #uCase( out.verb )#: #out.requestUrl#" );
		if ( structKeyExists( out, "body" ) ) {
			this.debugLog( out.body );
		}
		// throttle requests by sleeping the thread to prevent overloading api
		if ( this.lastRequest > 0 && this.throttle > 0 ) {
			out.delay= this.throttle - ( getTickCount() - this.lastRequest );
			if ( out.delay > 0 ) {
				this.debugLog( "Pausing for #out.delay#/ms" );
				sleep( out.delay );
			}
		}
		cftimer( type="debug", label="discogs request" ) {
			cfhttp( result="http", method=out.verb, url=out.requestUrl, charset="UTF-8", throwOnError=false, userAgent=this.userAgent, timeOut=this.httpTimeOut ) {
				if ( out.verb == "POST" || out.verb == "PUT" || out.verb == "PATCH" ) {
					cfhttpparam( name="content-type", type="header", value="application/json" );
				}
				if ( structKeyExists( out, "body" ) ) {
					cfhttpparam( type="body", value=out.body );
				}
			}
			if ( this.throttle > 0 ) {
				this.lastRequest= getTickCount();
				server.discogs_lastRequest= this.lastRequest;
			}
		}
		out.response= toString( http.fileContent );
		out.statusCode= http.responseHeader.Status_Code ?: 500;
		this.debugLog( out.statusCode );
		if ( left( out.statusCode, 1 ) == 4 || left( out.statusCode, 1 ) == 5 ) {
			out.success= false;
			out.error= "status code error: #out.statusCode#";
		} else if ( out.response == "Connection Timeout" || out.response == "Connection Failure" ) {
			out.error= out.response;
		} else if ( left( out.statusCode, 1 ) == 2 ) {
			out.success= true;
		}
		// parse response 
		try {
			out.data= deserializeJSON( out.response );
			if ( isStruct( out.data ) && structKeyExists( out.data, "error" ) ) {
				out.success= false;
				out.error= out.data.error;
			} else if ( isStruct( out.data ) && structKeyExists( out.data, "status" ) && out.data.status == 400 ) {
				out.success= false;
				out.error= out.data.detail;
			}
		} catch (any cfcatch) {
			out.error= "JSON Error: " & (cfcatch.message?:"No catch message") & " " & (cfcatch.detail?:"No catch detail");
		}
		if ( len( out.error ) ) {
			out.success= false;
		}
		return out;
	}


	// ---------------------------------------------------------------------------- 
	// ITEMS 
	// ---------------------------------------------------------------------------- 

	struct function searchByUPC(required string barcode) {
		return this.apiRequest( api= "GET /database/search?barcode={barcode}", argumentCollection= arguments );
	}

	struct function search(required string q) {
		return this.apiRequest( api= "GET /database/search?q={q}", argumentCollection= arguments );
	}

	struct function release(required string release_id) {
		return this.apiRequest( api= "GET /releases/{release_id}", argumentCollection= arguments );
	}

	// ---------------------------------------------------------------------------- 
	// MARKETPLACE 
	// ---------------------------------------------------------------------------- 
	
	// BROKEN 
	// struct function addOrderFeedback(required string order_id, required string rating, required string message) {
	// 	return this.apiRequest( api= "POST /marketplace/orders/{order_id}/feedback?token={token}", argumentCollection= arguments );
	// }

	struct function listInventory(required string username, string status= "", string sort= "", string sort_order= "", numeric page= 1, numeric per_page= 50) {
		return this.apiRequest( api= "GET /users/{username}/inventory", argumentCollection= arguments );
	}

	struct function getOrder(required string order_id) {
		return this.apiRequest( api= "GET /marketplace/orders/{order_id}?token={token}", argumentCollection= arguments );
	}

	struct function listOrders(string status= "", string sort= "", string sort_order= "", numeric page= 1, numeric per_page= 50) {
		return this.apiRequest( api= "GET /marketplace/orders?token={token}", argumentCollection= arguments );
	}

	struct function updateOrder(required string order_id, required string status) {
		return this.apiRequest( api= "POST /marketplace/orders/{order_id}?token={token}", argumentCollection= arguments );
	}

	struct function addOrderMessage(required string order_id, required string message, string status= "") {
		return this.apiRequest( api= "POST /marketplace/orders/{order_id}/messages?token={token}", argumentCollection= arguments );
	}

	string function structToQueryString(required struct stInput, string sUrl= "", boolean bEncode= true) {
		var sOutput= "";
		var sItem= "";
		var sValue= "";
		var amp= ( find( "?", arguments.sUrl ) ? "&" : "?" );
		for ( sItem in stInput ) {
			sValue= stInput[ sItem ];
			if ( !isNull( sValue ) && len( sValue ) ) {
				if ( bEncode ) {
					sOutput &= amp & sItem & "=" & urlEncodedFormat( sValue );
				} else {
					sOutput &= amp & sItem & "=" & sValue;
				}
				amp= "&";
			}
		}
		return sOutput;
	}

}
