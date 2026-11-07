package shinku.handling.tools;

import shinku.http.HttpMessages.HttpResponse;
import shinku.std.URL;
import shinku.Console.Logger;
import haxe.io.Error;
import shinku.http.HttpMessages.HttpRequest;

enum CookieSameSitePolicy {
	None;
	Lax;
	Strict;
}

typedef CookieSerializeOptions = {
	?domain:String,
	?expires:Date,
	?httpOnly:Bool,
	?maxAge:Int,
	?path:String,
	?sameSite:CookieSameSitePolicy,
	?secure:Bool
}

typedef SetCookieDefinition = {
	name:String,
	value:String,
	opts:CookieSerializeOptions,

	isDeleted:Bool
}

typedef CookieDefinition = {name:String, value:String}

final class Cookies {
	private var requestCookies:Array<CookieDefinition>;
	private var setCookies:Array<SetCookieDefinition>;

	public function new(req:HttpRequest) {
		this.requestCookies = [];
		this.setCookies = [];

		var cookieHeaderValues = req.getHeaderValues("cookie");

		for (header in cookieHeaderValues) {
			var start = 0;
			var length = header.length;

			while (start < length) {
				var end = header.indexOf(";", start);
				if (end == -1)
					end = length;
				var separator = header.indexOf("=", start);
				if (separator != -1 && separator < end) {
					var name = StringTools.trim(header.substring(start, separator));
					var value = StringTools.trim(header.substring(separator + 1, end));

					if (value.length >= 2 && value.charAt(0) == '"' && value.charAt(value.length - 1) == '"')
						value = value.substring(1, value.length - 1);

					if (isValidName(name)) {
						requestCookies.push({name: name, value: value});
					} else {
						#if dev
						Logger.warn("The request for", req.status.target,
							"has a cookie header with a invalid name: '"
							+ name
							+ "' in header value:\n"
							+ header
							+ "\nIt will be ignored. This warning will not appear in production builds.");
						#end
					}
				}
				start = end + 1;
			}
		}
	}

	/**
	 * Retrieves a cookie by its name.
	 *
	 * Cookies set or deleted through this instance take precedence over
	 * cookies received in the original HTTP request.
	 *
	 * Cookie values are not decoded. You might want to manually URL.decodeURIComponent on the value if applicable.
	 *
	 * @param name The name of the cookie to retrieve.
	 * @return The cookie definition if it exists and has not been deleted, or null otherwise.
	 * @throws Error.Custom If the cookie name is invalid.
	 */
	public function get(name:String):Null<CookieDefinition> {
		this.assertValidName(name);

		for (cookie in setCookies) {
			if (cookie.name == name) {
				return cookie.isDeleted ? null : {
					name: cookie.name,
					value: cookie.value
				};
			}
		}

		for (cookie in requestCookies) {
			if (cookie.name == name)
				return {
					name: cookie.name,
					value: cookie.value
				};
		}
		return null;
	}

	/**
	 * Checks whether a cookie exists.
	 *
	 * Cookies deleted through this instance are considered *dead* (aka deleted),
	 * even if they were originally present in the HTTP request.
	 *
	 * @param name The name of the cookie to check.
	 * @return True if the cookie exists and has not been deleted, false otherwise.
	 * @throws Error.Custom If the cookie name is invalid.
	 */
	public function exists(name:String) {
		this.assertValidName(name);

		for (cookie in setCookies) {
			if (cookie.name == name) {
				return cookie.isDeleted ? false : true;
			}
		}
		for (cookie in requestCookies) {
			if (cookie.name == name)
				return true;
		}
		return false;
	}

	/**
	 * Retrieves all cookies currently available to this instance.
	 *
	 * Cookies set through this instance override cookies with the same name
	 * from the original request. Deleted cookies are excluded.
	 *
	 * @return An array containing all existing cookie definitions.
	 */
	public function getAll():Array<CookieDefinition> {
		final existingOnes = this.setCookies.map(v -> v.name);
		return this.setCookies.filter(v -> !v.isDeleted)
			.map(v -> ({name: v.name, value: v.value}))
			.concat(requestCookies.filter(v -> !existingOnes.contains(v.name)).map(v -> ({name: v.name, value: v.value})));
	}

	/**
	 * Marks a cookie for deletion by adding an expired Set-Cookie definition on outbound requests.
	 *
	 * The cookie is assigned a maximum age of zero and an expiration date
	 * in the past. Any previously queued definition matching its name,
	 * path, and domain is replaced.
	 *
	 * @param name The name of the cookie to delete.
	 * @param opts Optional cookie serialization options, such as its domain and path.
	 * @throws Error.Custom If the cookie name, path, or domain is invalid.
	 */
	public function delete(name:String, opts:CookieSerializeOptions = {}) {
		this.assertValidName(name);
		this.assertPathName(opts.path ?? "/");
		this.assertDomainName(opts.domain ?? "localhost");
		this.filterOut(name, opts);

		var o = setDefaultsFor(opts);
		o.maxAge = 0;
		// February 24.. 1982, what a specific date, dont you think? a very.. maybe a very sunny day in Santa Clara, California.
		o.expires = new Date(1982, 1, 24, 12, 5, 23);

		this.setCookies.push({
			name: name,
			value: "",
			opts: o,
			isDeleted: true
		});
	}

	/**
	 * Sets a cookie by adding a Set-Cookie definition to this instance.
	 *
	 * If a previously queued cookie has the same name, path, and domain,
	 * it is replaced. 
	 *
	 * Default values: 
	 *
	 *   - If SameSite is set to "None", the `secure` field is always set to true.
	 *   - Path is `/` by default.
	 *   - Cookies set through here will be by default **http only cookies**, change this through the `opt` parameter.
	 *
	 *
	 * @param name The name of the cookie.
	 * @param value The value to store in the cookie.
	 * @param opts The options controlling cookie serialization.
	 * @throws Error.Custom If the cookie name, path, or domain is invalid.
	 */
	public function set(name:String, value:String, opts:CookieSerializeOptions) {
		this.assertValidName(name);
		this.assertPathName(opts.path ?? "/");
		this.assertDomainName(opts.domain ?? "localhost");
		this.filterOut(name, opts);

		this.setCookies.push({
			name: name,
			value: value,
			opts: setDefaultsFor(opts),
			isDeleted: false
		});
	}

	/**
	 * Serializes a cookie into a Set-Cookie header value.
	 *
	 * The cookie value is URL-encoded, and the provided options are
	 * converted into their corresponding Set-Cookie attributes.
	 * Default options are applied before serialization (see Cookies#set for defaults).
	 *
	 * @param name The name of the cookie.
	 * @param value The value to serialize.
	 * @param opts The options controlling cookie serialization.
	 * @return The serialized Set-Cookie header value.
	 * @throws Error.Custom If the cookie name or path is invalid.
	 */
	public function serialize(name:String, value:String, opts:CookieSerializeOptions) {
		this.assertValidName(name);
		final o = setDefaultsFor(opts);
		this.assertPathName(o.path ?? "/");
		final parts = [name + "=" + URL.encodeURIComponent(value)];
		if (o.maxAge != null)
			parts.push("Max-Age=" + o.maxAge);
		if (o.domain != null)
			parts.push("Domain=" + o.domain);
		if (o.path != null)
			parts.push("Path=" + o.path);
		if (o.expires != null)
			parts.push("Expires=" + HttpResponse.rfc6265Date(o.expires));
		if (o.httpOnly == true)
			parts.push("HttpOnly");
		if (o.secure == true)
			parts.push("Secure");
		if (o.sameSite != null)
			parts.push("SameSite=" + o.sameSite.getName());
		return parts.join("; ");
	}

	private function setDefaultsFor(opts:CookieSerializeOptions):CookieSerializeOptions {
		return {
			domain: opts.domain,
			secure: opts.sameSite == None ? true : (opts.secure ?? false),
			sameSite: opts.sameSite ?? Lax,
			path: opts.path ?? "/",
			maxAge: opts.maxAge,
			httpOnly: opts.httpOnly ?? true,
			expires: opts.expires
		};
	}

	/***
		# INTERNAL USAGE ONLY

		Dont call this!.. unless you know what you're doing?
		No seriously, DynamicRouter already applies this for you, there is no reason to call this yourself.

	**/
	public function installTo(http:HttpResponse) {
		Logger.debug("Installing..");
		http.setHeader("Set-Cookie", this.setCookies.map(v -> serialize(v.name, v.value, v.opts)));
	}

	private function isValidName(name:String)
		return ~/^[!#$%&'*+\-.^_`|~0-9a-zA-Z]+$/.match(name);

	private function isValidPath(path:String):Bool
		return ~/^[\x20-\x3A\x3C-\x7E]*$/.match(path);

	private function assertDomainName(domain:String) {
		if (domain != null && !~/^[A-Za-z0-9.-]+$/.match(domain))
			throw Error.Custom("This is not a valid domain for a cookie: '" + domain + "'. Sorry.");
	}

	private function assertValidName(name:String) {
		if (!isValidName(name))
			throw Error.Custom("This is not a valid RFC 6265 token: '" + name + "' and it cannot be used as a name for a cookie. Sorry.");
	}

	private function assertPathName(path:String) {
		if (!isValidPath(path))
			throw Error.Custom("This is not a valid path for a cookie: '" + path + "'. Sorry.");
	}

	private function filterOut(name:String, opts:CookieSerializeOptions) {
		this.setCookies = this.setCookies.filter(v -> v.name != name || v.opts.path != (opts.path ?? "/") || v.opts.domain != opts.domain);
	}
}
