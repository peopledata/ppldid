class DidsController < ApplicationController
    include ApplicationHelper
    include ActionController::MimeResponds

    # respond only to JSON requests
    respond_to :json
    respond_to :html, only: []
    respond_to :xml, only: []

    def show
        options = {}
        if ENV["DID_LOCATION"].to_s != ""
            options[:location] = ENV["DID_LOCATION"].to_s
            if options[:doc_location].nil?
                options[:doc_location] = options[:location]
            end
            if options[:log_location].nil?
                options[:log_location] = options[:location]
            end
        end

        did = params[:did]
        result = resolve_did(did, options)
        if result["error"] != 0
            puts "Error: " + result["message"].to_s
            render json: {"error": result["message"].to_s}.to_json,
                   status: 500
        else
            render json: result["doc"],
                   status: 200
        end
    end

    def raw
        options = {}
        if ENV["DID_LOCATION"].to_s != ""
            options[:location] = ENV["DID_LOCATION"].to_s
            if options[:doc_location].nil?
                options[:doc_location] = options[:location]
            end
            if options[:log_location].nil?
                options[:log_location] = options[:location]
            end
        end

        did = remove_location(params[:did])
        result = local_retrieve_document(did)
        if result.nil?
            render json: {"error": "cannot find " + did.to_s}.to_json,
                   status: 404
        else
            log_result = local_retrieve_log(did)
            render json: {"doc": result, "log": log_result}.to_json,
                   status: 200
        end
    end

    def create
        # input
        input = params.except(:controller, :action)
        did = input["did"]
        didDocument = input["did-document"]
        logs = input["logs"]

        # validate input
        if did.nil? || did == {}
            render json: {"error": "missing DID"},
                   status: 400
            return
        end
        if did[0,8] != "did:ppld:"
            render json: {"error": "invalid DID"},
                   stauts: 412
            return
        end
        didLocation = did.split(LOCATION_PREFIX)[1] rescue ""
        didHash = did.split(LOCATION_PREFIX)[0] rescue did
        didHash = didHash.delete_prefix("did:ppld:")
        if !Did.find_by_did(didHash).nil?
            render json: {"message": "DID already exists"},
                   status: 200
            return
        end

        if didDocument.nil?
            render json: {"error": "missing did-document"},
                   status: 400
            return
        end
        didDoc = JSON.parse(didDocument.to_json) rescue nil
        if didDoc.nil?
            render json: {"error": "cannot parse did-document"},
                   status: 412
            return
        end
        if didDoc["doc"].nil?
            render json: {"error": "missing 'doc' key in did-document"},
                   status: 412
            return
        end
        if didDoc["key"].nil?
            render json: {"error": "missing 'key' key in did-document"},
                   status: 412
            return
        end
        if didDoc["log"].nil?
            render json: {"error": "missing 'log' key in did-document"},
                   status: 412
            return
        end
        if didHash != Ppldid.hash(Ppldid.canonical(didDocument))
            render json: {"error": "DID does not match did-document"},
                   status: 400
            return
        end

        if !logs.is_a? Array
            render json: {"error": "log is not an array"},
                   status: 412
            return
        end
        if logs.count < 2
            render json: {"error": "not enough log entries (min: 2)"},
                   status: 412
            return
        end
        log_entry_hash = ""
        logs.each do |item|
            if item["op"] == 0 # TERMINATE
                log_entry_hash = Ppldid.hash(Ppldid.canonical(item))
            end
        end
        if log_entry_hash != ""
            did_log = didDoc["log"].to_s
            did_log = did_log.split(LOCATION_PREFIX)[0] rescue did_log
            if did_log != log_entry_hash
                render json: {"error": "invalid 'log' key in did-document"},
                       status: 412
                return
            end
        end

        @did = Did.find_by_did(didHash)
        if @did.nil?
            Did.new(did: didHash, doc: didDocument.to_json).save
        end
        logs.each do |item|
            if item["op"] == 1 # REVOKE
                my_hash = Ppldid.hash(Ppldid.canonical(item.except("previous")))
                @log = Log.find_by_oyd_hash(my_hash)
                if @log.nil?
                    Log.new(did: didHash, item: item.to_json, oyd_hash: my_hash, ts: Time.now.to_i).save
                end
            else
                my_hash = Ppldid.hash(Ppldid.canonical(item))
                @log = Log.find_by_oyd_hash(my_hash)
                if @log.nil?
                    Log.new(did: didHash, item: item.to_json, oyd_hash: my_hash, ts: Time.now.to_i).save
                end
            end
        end

        render plain: "",
               stauts: 200
    end

    def delete
        @did = Did.find_by_did(params[:did].to_s)
        if @did.nil?
            render json: {"error": "DID not found"},
                   status: 404
            return
        end
        keys = JSON.parse(@did.doc)["key"]
        public_doc_key = keys.split(":")[0]
        public_rev_key = keys.split(":")[1]
        private_doc_key = params[:dockey]
        private_rev_key = params[:revkey]
        if public_doc_key == Ppldid.public_key(private_doc_key).first &&
           public_rev_key == Ppldid.public_key(private_rev_key).first
                Log.where(did: params[:did].to_s).destroy_all
                Did.where(did: params[:did].to_s).destroy_all
                render plain: "",
                       status: 200
        else
            puts "Doc key: " + public_doc_key.to_s + " <=> " + Ppldid.public_key(private_doc_key).first.to_s
            puts "Rev key: " + public_rev_key.to_s + " <=> " + Ppldid.public_key(private_rev_key).first.to_s
            render json: {"error": "invalid keys"},
                   status: 403
        end
    end

    # Uniresolver functions =====================
    def resolve
        options = {}
        did = params[:did]
        result = resolve_did(did, options)
        if result["error"] != 0
            render json: {"error": result["message"].to_s}.to_json,
                   status: result["error"]
        else
            w3c_did = Ppldid.w3c(result, options)
            render plain: w3c_did.to_json,
                   mime_type: Mime::Type.lookup("application/ld+json"),
                   content_type: 'application/ld+json',
                   status: 200
        end
    end

    # Uniregistrar functions ====================

    # input
    # {
    #     "options": {
    #         "ledger": "test",
    #         "keytype": "ed25519"
    #     },
    #     "secret": {},
    #     "didDocument": {}
    # }
    def uniregistrar_create
        jobId = params[:jobId] rescue nil
        if jobId.nil?
            jobId = SecureRandom.uuid
        end
        didDocument = params[:didDocument]
        params.permit!
        options = params[:options] || {}
        options[:return_secrets] = true
        secret = params[:secret] || {}
        options = options.to_hash.merge(secret.to_hash).transform_keys(&:to_sym)

        if options[:doc_location] == "local"
            render json: {"error": "location not supported"},
                   status: 500
            return
        end

        if options[:location].to_s != ""
            if !options[:location].start_with?("http")
                options[:location] = "https://" + options[:location]
            end
        end

        if options[:doc_location].nil?
            options[:doc_location] = options[:location]
        end
        if options[:doc_location].to_s != ""
            if !options[:doc_location].start_with?("http")
                options[:doc_location] = "https://" + options[:doc_location]
            end
        end

        if options[:log_location].nil?
            options[:log_location] = options[:location]
        end
        if options[:log_location].to_s != ""
            if !options[:log_location].start_with?("http")
                options[:log_location] = "https://" + options[:log_location]
            end
        end

        doc = didDocument
        did_obj = JSON.parse(doc.to_json) rescue nil
        if !did_obj.nil? && did_obj.is_a?(Hash)
            if did_obj["@context"] == "https://www.w3.org/ns/did/v1"
                doc = Ppldid.fromW3C(didDocument, options)
            end
        end
        
        preprocessed = false
        msg = ""
        if !did_obj.nil? && did_obj.is_a?(Hash)
            if did_obj["doc"].to_s != "" && did_obj["key"].to_s != "" && did_obj["log"].to_s != ""
                if !options[:log_create].nil? && !options[:log_terminate].nil?
                    preprocessed = true

                    # perform sanity checks on input data
                    # is doc in log create record == Hash(did_document)
                    if Ppldid.hash(Ppldid.canonical(did_obj)) != options[:log_create]["doc"]
                        render json: {"error": "invalid input data (create log does not match DID document)"},
                               status: 400
                        return
                    end

                    # check valid signature in log create record
                    doc_pubkey = did_obj["key"].split(":").first.to_s
                    success, msg = Ppldid.verify(options[:log_create]["doc"], options[:log_create]["sig"], doc_pubkey)
                    if !success
                        render json: {"error": "invalid input data (create log has invalid signature)"},
                               status: 400
                        return
                    end

                    # check valid signature in terminate record
                    success, msg = Ppldid.verify(options[:log_terminate]["doc"], options[:log_terminate]["sig"], doc_pubkey)
                    if !success
                        render json: {"error": "invalid input data (terminate log has invalid signature)"},
                               status: 400
                        return
                    end

                    # create DID
                    did = "did:ppld:" + Ppldid.hash(Ppldid.canonical(did_obj))
                    logs = [options[:log_create], options[:log_terminate]]
                    success, msg = Ppldid.publish(did, did_obj, logs, options)
                    if success
                        w3c_input = {
                            "did" => did,
                            "doc" => didDocument
                        }
                        status = {
                            "did" => did,
                            "doc" => didDocument,
                            "doc_w3c" => Ppldid.w3c(w3c_input, options),
                            "log" => logs,
                            "private_key" => "",
                            "revocation_key" => "",
                            "revocation_log" => []
                        }
                    else
                        status = nil
                    end
                end
            end
        end
        if !preprocessed
            status, msg = Ppldid.create(doc, options)
        end
        if status.nil?
            render json: {"error": msg},
                   status: 500
        else
            retVal = {
                "didState": {
                    "did": Ppldid.percent_encode(status["did"]),
                    "state": "finished",
                    "secret": {
                        "documentKey": status["private_key"],
                        "revocationKey": status["revocation_key"],
                        "revocationLog": status["revocation_log"]
                    },
                    "didDocument": status["doc_w3c"]
                },
                "didRegistrationMetadata": {},
                "didDocumentMetadata": {
                    "did": Ppldid.percent_encode(status["did"]),
                    "registry": Ppldid.get_location(status["did"].to_s),
                    "log_hash": status["doc"]["log"].to_s,
                    "log": status["log"]
                }
            }
            render json: retVal.to_json,
                   status: 200
        end
    end

    # input
    # {
    #     "identifier": "did:sov:WRfXPg8dantKVubE3HX8pw",
    #     "options": {
    #         "ledger": "test",
    #         "keytype": "ed25519"
    #     },
    #     "secret": {},
    #     "didDocument": {}
    # }
    def uniregistrar_update
        jobId = params[:jobId] rescue nil
        if jobId.nil?
            jobId = SecureRandom.uuid
        end
        old_did = params[:identifier]
        didDocument = params[:didDocument]

        params.permit!
        options = params[:options] || {}
        options[:return_secrets] = true
        secret = params[:secret] || {}
        options = options.to_hash.merge(secret.to_hash).transform_keys(&:to_sym)

        if options[:doc_location] == "local"
            render json: {"error": "location not supported"},
                   status: 500
            return
        end

        did_obj = JSON.parse(didDocument.to_json) rescue nil
        if !did_obj.nil? && did_obj.is_a?(Hash)
            if did_obj["@context"] == "https://www.w3.org/ns/did/v1"
                did_obj = Ppldid.fromW3C(did_obj, options)
            end
        end

        preprocessed = false
        msg = ""
        if !did_obj.nil? && did_obj.is_a?(Hash)
            if !options[:log_revoke].nil? && !options[:log_update].nil? && !options[:log_terminate].nil?
                preprocessed = true

                # perform sanity checks on input data =========

                # check valid signature in update create record
                doc_pubkey = did_obj["key"].split(":").first.to_s
                old_doc_location = Ppldid.get_location(old_did)
                old_didDocument = Ppldid.retrieve_document_raw(old_did, "", old_doc_location, {})
                old_doc_pubkey = old_didDocument.first["doc"]["key"].split(":").first.to_s
                success, msg = Ppldid.verify(options[:log_update]["doc"], options[:log_update]["sig"], old_doc_pubkey)
                if !success
                    render json: {"error": "invalid input data (update log has invalid signature)"},
                           status: 400
                    return
                end

                # update DID
                did = "did:ppld:" + Ppldid.hash(Ppldid.canonical(did_obj))
                logs = [options[:log_revoke], options[:log_update], options[:log_terminate]]
                success, msg = Ppldid.publish(did, did_obj, logs, options)
                if success
                    w3c_input = {
                        "did" => did,
                        "doc" => did_obj
                    }
                    status = {
                        "did" => did,
                        "doc" => did_obj,
                        "doc_w3c" => Ppldid.w3c(w3c_input, options),
                        "log" => logs,
                        "private_key" => "",
                        "revocation_key" => "",
                        "revocation_log" => []
                    }
                else
                    status = nil
                end
            end
        end

        if !preprocessed
            status, msg = Ppldid.update(did_obj, old_did, options)
        end
        if status.nil?
            render json: {"error": msg},
                   status: 500
        else
            retVal = {
                "didState": {
                    "did": Ppldid.percent_encode(status["did"]),
                    "state": "finished",
                    "secret": {
                        "documentKey": status["private_key"],
                        "revocationKey": status["revocation_key"],
                        "revocationLog": status["revocation_log"]
                    },
                    "didDocument": status["doc_w3c"]
                },
                "didRegistrationMetadata": {},
                "didDocumentMetadata": {
                    "did": Ppldid.percent_encode(status["did"]),
                    "registry": Ppldid.get_location(status["did"].to_s),
                    "log_hash": status["doc"]["log"].to_s,
                    "log": status["log"]
                }
            }
            render json: retVal.to_json,
                   status: 200
        end
    end

    # input
    # {
    #     "identifier": "did:sov:WRfXPg8dantKVubE3HX8pw",
    #     "options": {
    #         "ledger": "test",
    #         "keytype": "ed25519"
    #     },
    #     "secret": {}
    # }
    def uniregistrar_deactivate
        jobId = params[:jobId] rescue nil
        if jobId.nil?
            jobId = SecureRandom.uuid
        end
        did = params[:identifier]
        params.permit!
        options = params[:options] || {}
        options[:return_secrets] = true
        secret = params[:secret] || {}
        options = options.to_hash.merge(secret.to_hash).transform_keys(&:to_sym)
        if options[:old_doc_pwd].nil? && !options[:doc_pwd].nil?
            options[:old_doc_pwd] = options[:doc_pwd]
        end
        if options[:old_rev_pwd].nil? && !options[:rev_pwd].nil?
            options[:old_rev_pwd] = options[:rev_pwd]
        end
        if options[:doc_location] == "local"
            render json: {"error": "location not supported"},
                   status: 500
            return
        end

        preprocessed = false
        msg = ""
        if !options[:log_revoke].nil?
            preprocessed = true

            # perform sanity checks on input data =========

        end
        if !preprocessed
            status, msg = Ppldid.revoke(did, options)
        end

        if status.nil?
            render json: {"error": msg},
                   status: 500
        else
            retVal = {
                "didState": {
                    "did": Ppldid.percent_encode(did),
                    "state": "finished",
                },
                "didRegistrationMetadata": {},
                "didDocumentMetadata": {
                    "did": Ppldid.percent_encode(status["did"]),
                    "registry": Ppldid.get_location(status["did"].to_s)
                }
            }
            render json: retVal.to_json,
                   status: 200
        end
    end    
end