export namespace main {
	
	export class Device {
	    deviceID: string;
	    name: string;
	    addresses: string[];
	    compression: string;
	    certName: string;
	    introducer: boolean;
	
	    static createFrom(source: any = {}) {
	        return new Device(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.deviceID = source["deviceID"];
	        this.name = source["name"];
	        this.addresses = source["addresses"];
	        this.compression = source["compression"];
	        this.certName = source["certName"];
	        this.introducer = source["introducer"];
	    }
	}
	export class Folder {
	    id: string;
	    label: string;
	    path: string;
	
	    static createFrom(source: any = {}) {
	        return new Folder(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.label = source["label"];
	        this.path = source["path"];
	    }
	}

}

