import Foundation

/// Support for RFC1123 formatted date strings.
/// http://blog.mro.name/2009/08/nsdateformatter-http-header/ and
/// http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.3.1
public extension Date {

    /// Creates a date by parsing an RFC1123 'Full-Date' string, falling back to the
    /// RFC850 and asctime formats also permitted by the HTTP spec.
    init?(rfc1123 string: String) {
        guard let date = rfc1123Formatter.date(from: string)
            ?? rfc850Formatter.date(from: string)
            ?? asctimeFormatter.date(from: string) else {
            return nil
        }

        self = date
    }

    /// This date formatted as an RFC1123 'Full-Date' string.
    var rfc1123String: String {
        rfc1123OutputFormatter.string(from: self)
    }
}

private let rfc1123Locale = Locale(identifier: "en_US")
private let gmtTimeZone = TimeZone(abbreviation: "GMT")

private let rfc1123Formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = rfc1123Locale
    formatter.timeZone = gmtTimeZone
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
    return formatter
}()

private let rfc850Formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = rfc1123Locale
    formatter.timeZone = gmtTimeZone
    formatter.dateFormat = "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss z"
    return formatter
}()

private let asctimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = rfc1123Locale
    formatter.timeZone = gmtTimeZone
    formatter.dateFormat = "EEE MMM d HH':'mm':'ss yyyy"
    return formatter
}()

private let rfc1123OutputFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = rfc1123Locale
    formatter.timeZone = gmtTimeZone
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
    return formatter
}()
